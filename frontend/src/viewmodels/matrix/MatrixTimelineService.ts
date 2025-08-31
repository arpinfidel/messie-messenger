import * as matrixSdk from 'matrix-js-sdk';
import { EventType, MatrixEvent, Room } from 'matrix-js-sdk';
import { writable, type Writable } from 'svelte/store';

import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixDataStore } from './core/MatrixDataStore';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import type { ImageContent } from 'matrix-js-sdk/lib/@types/media';
import { MediaResolver } from './core/MediaResolver';
import { AvatarResolver } from './core/AvatarResolver';

export interface MatrixMessage {
  id: string;
  sender: string;
  senderDisplayName: string; // Add this line
  senderAvatarUrl?: string;
  description: string;
  timestamp: number;
  isSelf: boolean;
  msgtype?: string;
  imageUrl?: string;
  // For future enhancements/debugging
  mxcUrl?: string;
}

export class MatrixTimelineService {
  private _timelineItems: Writable<IMatrixTimelineItem[]> = writable([]);
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;
  private listRefreshInFlight = false;
  private pendingLiveEvents: Array<{ ev: MatrixEvent; room: Room }> = [];
  private mediaResolver = new MediaResolver(() => this.client);
  private avatarResolver = new AvatarResolver(() => this.client, { maxMemEntries: 200, maxDbEntries: 200 });

  constructor(
    private readonly ctx: {
      getClient: () => matrixSdk.MatrixClient | null;
      isStarted: () => boolean;
      getHydrationState: () => 'idle' | 'syncing' | 'decrypting' | 'ready';
    },
    private readonly store: MatrixDataStore,
    private readonly layer: MatrixDataLayer
  ) {}

  private get client() {
    return this.ctx.getClient();
  }

  getTimelineItemsStore(): Writable<IMatrixTimelineItem[]> {
    return this._timelineItems;
  }

  /** Unified room list with their latest message preview.
   * Compute strictly from our MatrixDataStore instead of querying the SDK.
   */
  async fetchAndSetTimelineItems(): Promise<void> {
    if (!this.ctx.isStarted() || this.ctx.getHydrationState() !== 'ready') return;
    if (this.listRefreshInFlight) return;

    this.listRefreshInFlight = true;
    try {
      const rooms = this.store.getRooms();

      // Ensure at least one event (latest) is present to build previews.
      // Do this via the data layer, not by reading the SDK directly here.
      for (const r of rooms) {
        if (!this.store.getLatestEvent(r.id)) {
          try {
            await this.layer.fetchInitial(r.id, 1);
          } catch {}
        }
      }

      const items = rooms.map((room) => {
        const last = this.store.getLatestEvent(room.id);
        let description = 'No recent messages';
        // Prefer stored latestTimestamp (may be loaded from IndexedDB even if events tail is sparse)
        let timestamp = room.latestTimestamp || 0;
        if (last) {
          const preview = this.repoEventToPreview(last);
          description = preview.description;
          timestamp = last.originServerTs || timestamp || 0;
        }
        let avatarUrl: string | undefined;
        try {
          const mxc = (room as any).avatarUrl as string | null | undefined;
          if (mxc) {
            // kick off a prefetch; do not block the list
            this.avatarResolver.prefetch(mxc, { w: 64, h: 64, method: 'crop' }).catch(() => {});
            const c = this.client as any;
            avatarUrl = c?.mxcUrlToHttp?.(mxc, 64, 64, 'crop', false, true, false) || undefined;
          }
        } catch {}
        return new MatrixTimelineItem({
          id: room.id,
          type: 'matrix',
          title: room.name || room.id,
          description,
          avatarUrl,
          timestamp,
        });
      });

      // Sort items by timestamp in descending order (latest first)
      items.sort((a, b) => b.timestamp - a.timestamp);
      this._timelineItems.set(items);
    } finally {
      this.listRefreshInFlight = false;
    }
  }

  scheduleTimelineRefresh(delay = 200) {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(async () => {
      this.refreshTimer = null;
      if (this.ctx.getHydrationState() !== 'ready' || this.listRefreshInFlight) return;

      this.listRefreshInFlight = true;
      try {
        await this.fetchAndSetTimelineItems();
      } finally {
        this.listRefreshInFlight = false;
      }
    }, delay);
  }

  /** Live pipeline: ingest event into store via data layer, then update preview. */
  async pushTimelineItemFromEvent(ev: MatrixEvent, room: Room) {
    await this.layer.ingestLiveEvent(ev, room);

    const last = this.store.getLatestEvent(room.roomId);
    const fallbackTs =
      this.store.getRooms().find((r) => r.id === room.roomId)?.latestTimestamp || 0;
    const timestamp = last?.originServerTs ?? fallbackTs;
    const id = room.roomId;
    const title = room.name || room.roomId;
    const { description } = last ? this.repoEventToPreview(last) : { description: '' };

    let avatarUrl: string | undefined;
    try {
      const mxc = (room as any).getMxcAvatarUrl ? (room as any).getMxcAvatarUrl() : null;
      if (mxc) {
        const c = this.client as any;
        avatarUrl = c?.mxcUrlToHttp?.(mxc, 64, 64, 'crop', false, true, false) || undefined;
      }
    } catch {}

    const updated = new MatrixTimelineItem({
      id,
      type: 'matrix',
      title,
      description,
      avatarUrl,
      timestamp,
    });

    this._timelineItems.update((items) => {
      const idx = items.findIndex((it) => it.id === id);
      if (idx === -1) return [updated, ...items];
      const next = items.slice();
      if ((next[idx]?.timestamp ?? 0) <= timestamp) next[idx] = updated;
      return next;
    });
  }

  bufferLiveEvent(ev: MatrixEvent, room: Room) {
    this.pendingLiveEvents.push({ ev, room });
  }

  async flushPendingLiveEvents() {
    if (!this.pendingLiveEvents.length) return;
    for (const { ev, room } of this.pendingLiveEvents) {
      try {
        await this.pushTimelineItemFromEvent(ev, room);
      } catch {}
    }
    this.pendingLiveEvents.length = 0;
  }

  /* ---------------- Room messages API (delegates to repo) ---------------- */

  /** First page: from live timeline (repo.fetchInitial). */
  async getRoomMessages(
    roomId: string,
    fromToken: string | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    if (!fromToken) {
      const { events, toToken } = await this.layer.fetchInitial(roomId, limit);
      const messages = await this.mapRepoEventsToMessages(events);
      return { messages, nextBatch: toToken };
    }
    const page = await this.layer.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: await this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  async loadOlderMessages(
    roomId: string,
    fromToken?: string | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    // We ignore `fromToken` and use the store's backward token from live timeline.
    const page = await this.layer.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: await this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  clearRoomPaginationTokens(roomId: string) {
    this.layer.clearRoom(roomId);
  }

  /* ---------------- Mapping helpers ---------------- */

  private async mapRepoEventsToMessages(events: RepoEvent[]): Promise<MatrixMessage[]> {
    const currentUserId = this.store.getCurrentUserId() ?? '';
    const msgs: MatrixMessage[] = [];
    const resolvers: Array<Promise<void>> = [];
    for (const re of events.filter(
      (re) => re.type === EventType.RoomMessage || re.type === 'm.room.encrypted'
    )) {
      // Try to ensure we have decrypted content by consulting the SDK event if available
      let effectiveType = re.type;
      let effectiveContent: any = re.content;
      try {
        const c = this.client as any;
        const room = c?.getRoom(re.roomId!);
        const live = room?.getLiveTimeline?.();
        const sdkEv = live?.getEvents?.().find((e: any) => e.getId?.() === re.eventId);
        if (sdkEv) {
          await c?.decryptEventIfNeeded?.(sdkEv);
          effectiveType = sdkEv.getType?.() || effectiveType;
          effectiveContent = sdkEv.getContent?.() || effectiveContent;
        }
      } catch {}

      const { description } = this.repoEventToPreview({ ...re, type: effectiveType, content: effectiveContent } as RepoEvent);
      const isSelf = re.sender === currentUserId;
      // Prefer cached display name from store, then SDK membership, else MXID
      let senderDisplayName = this.store.getUserDisplayName(re.sender) || re.sender;
      if (!senderDisplayName) senderDisplayName = re.sender;
      if (senderDisplayName === re.sender) {
        try {
          const c = this.client;
          const room = c?.getRoom(re.roomId!);
          const member = room?.getMember(re.sender);
          if (member) senderDisplayName = (member as any).rawDisplayName || member.name || re.sender;
        } catch {}
      }
      const msgtype = effectiveContent?.msgtype;

      const msg: MatrixMessage = {
        id: re.eventId || `${Date.now()}-${Math.random()}`,
        sender: re.sender || 'unknown sender',
        senderDisplayName, // Assign display name
        senderAvatarUrl: undefined,
        description,
        timestamp: re.originServerTs || 0,
        isSelf,
        msgtype,
      };

      // Resolve sender avatar via avatarResolver (IDB-backed cache) and assign onto msg
      try {
        const mxc = this.store.getUser(re.sender)?.avatarUrl || undefined;
        if (mxc) {
          const p = this.avatarResolver
            .resolve(mxc, { w: 32, h: 32, method: 'crop' })
            .then((url) => { if (url) msg.senderAvatarUrl = url; })
            .catch(() => {});
          resolvers.push(p);
        }
      } catch {}

      if (msgtype === matrixSdk.MsgType.Image) {
        const content = effectiveContent as ImageContent;
        msg.mxcUrl = content.file?.url ?? content.url;
        const p = this.mediaResolver
          .resolveImage(content)
          .then((blobUrl) => {
            if (blobUrl) msg.imageUrl = blobUrl;
          })
          .catch(() => {});
        resolvers.push(p);
      }

      msgs.push(msg);
    }

    if (resolvers.length) await Promise.allSettled(resolvers);
    return msgs;
  }

  // Media cache management
  clearMediaCache(): void {
    this.mediaResolver.clear();
    this.avatarResolver.clear();
  }

  /** Create a human preview from RepoEvent content (works for decrypted encrypted). */
  private repoEventToPreview(re: RepoEvent): { description: string } {
    let c: any = re.content;
    // Fallback: try to decrypt via SDK if content doesn't look like a message
    if (!c?.body && re.type === 'm.room.encrypted') {
      try {
        const cli = this.client as any;
        const room = cli?.getRoom(re.roomId!);
        const live = room?.getLiveTimeline?.();
        const sdkEv = live?.getEvents?.().find((e: any) => e.getId?.() === re.eventId);
        if (sdkEv) {
          // Fire and forget; if it decrypts, content may already be clear
          try { cli?.decryptEventIfNeeded?.(sdkEv); } catch {}
          c = sdkEv.getContent?.() || c;
        }
      } catch {}
    }
    if (c.msgtype === matrixSdk.MsgType.Image) {
      const body = c.body;
      return { description: `Image: ${typeof body === 'string' ? body : 'Image'}` };
    }
    const body = c.body;
    if (typeof body === 'string') return { description: body };

    const relates = c['m.relates_to'];
    if (relates?.rel_type === 'm.annotation') {
      const key = typeof c.key === 'string' ? (c.key as string) : undefined;
      if (key) {
        const name = this.store.getUserDisplayName(re.sender) || re.sender;
        return { description: `${name} reacted with ${key}` };
      }
    }
    if (relates?.rel_type === 'm.reference') {
      return { description: 'Replied to a message' };
    }
    return { description: 'This message could not be decrypted.' };
  }
}
