import * as matrixSdk from 'matrix-js-sdk';
import { EventType, MatrixEvent, Room } from 'matrix-js-sdk';
import { writable, type Writable, get } from 'svelte/store';

import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import type { ImageContent } from 'matrix-js-sdk/lib/@types/media';
import { MediaResolver } from './core/MediaResolver';
import { AvatarService } from './core/AvatarService';

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
  private pendingLiveEvents: Array<{ ev: MatrixEvent; room: Room }> = [];
  private mediaResolver = new MediaResolver(() => this.client);
  private readonly maxRooms = 30; // limit room list to most recent N

  constructor(
    private readonly ctx: {
      getClient: () => matrixSdk.MatrixClient | null;
      isStarted: () => boolean;
      getHydrationState: () => 'idle' | 'syncing' | 'decrypting' | 'ready';
    },
    private readonly layer: MatrixDataLayer,
    private readonly avatars: AvatarService
  ) {}

  private get client() {
    return this.ctx.getClient();
  }

  getTimelineItemsStore(): Writable<IMatrixTimelineItem[]> {
    return this._timelineItems;
  }

  /** Unified room list with their latest message preview.
   * Compute strictly from data provided by MatrixDataLayer instead of querying the SDK.
   */
  async fetchAndSetTimelineItems(): Promise<void> {
    const rooms = await this.layer.getRooms();
    // Sort rooms by latest activity and keep only top N
    const sortedRooms = rooms
      .slice()
      .sort((a, b) => (b.latestTimestamp ?? 0) - (a.latestTimestamp ?? 0));
    console.log('[MatrixVM] Rooms from data layer:', sortedRooms);
    const limitedRooms = sortedRooms.slice(0, this.maxRooms);

    console.log('[MatrixVM] fetchAndSetTimelineItems', limitedRooms);

    const items: IMatrixTimelineItem[] = [];
    const currentItems = get(this._timelineItems) as IMatrixTimelineItem[];
    for (const room of limitedRooms) {
      const last = (await this.layer.queryEventsByRoom(room.id, 1))[0];
      let description = 'No recent messages';
      let timestamp = room.latestTimestamp || 0;
      if (last) {
        const preview = this.repoEventToPreview(last);
        description = preview.description;
        timestamp = last.originServerTs || timestamp || 0;
      }
      // Reuse previous avatar if any; resolve lazily in background
      const prev = currentItems?.find((it) => it.id === room.id);
      const avatarUrl = prev?.avatarUrl;

      items.push(
        new MatrixTimelineItem({
          id: room.id,
          type: 'matrix',
          title: room.name || room.id,
          description,
          avatarUrl,
          timestamp,
        })
      );
    }

    // Sort and set immediately so UI renders fast
    items.sort((a, b) => b.timestamp - a.timestamp);
    this._timelineItems.set(items);

    // Resolve avatars in background with limited concurrency and patch items as they arrive
    const maxConcurrent = 6;
    let i = 0;
    const work = async () => {
      while (i < limitedRooms.length) {
        const idx = i++;
        const room = limitedRooms[idx];
        try {
          const url = await this.avatars.resolveRoomAvatar(room.id, room.avatarMxcUrl, {
            w: 64,
            h: 64,
            method: 'crop',
          });
          if (!url) continue;
          this._timelineItems.update((arr) => {
            const j = arr.findIndex((t) => t.id === room.id);
            if (j === -1) return arr;
            const updated = arr.slice();
            updated[j] = new MatrixTimelineItem({ ...updated[j], avatarUrl: url });
            return updated;
          });
        } catch {}
      }
    };
    // Kick off workers without awaiting completion
    for (let k = 0; k < Math.min(maxConcurrent, limitedRooms.length); k++) {
      work();
    }
  }

  /** Live pipeline: ingest event into store via data layer, then update preview. */
  async pushTimelineItemFromEvent(ev: MatrixEvent, room: Room) {
    await this.layer.ingestLiveEvent(ev, room);

    const last = (await this.layer.queryEventsByRoom(room.roomId, 1))[0];
    const rooms = await this.layer.getRooms();
    const fallbackTs = rooms.find((r) => r.id === room.roomId)?.latestTimestamp || 0;
    const timestamp = last?.originServerTs ?? fallbackTs;
    const id = room.roomId;
    const title = room.name || room.roomId;
    const { description } = last ? this.repoEventToPreview(last) : { description: '' };

    let avatarUrl: string | undefined;
    const roomMxc = room.getMxcAvatarUrl();
    avatarUrl = await this.avatars.resolveRoomAvatar(room.roomId, roomMxc || undefined, {
      w: 64,
      h: 64,
      method: 'crop',
    });

    const updated = new MatrixTimelineItem({
      id,
      type: 'matrix',
      title,
      description,
      // Keep previous avatar if resolve failed
      avatarUrl:
        avatarUrl ||
        (get(this._timelineItems).find((it) => it.id === id) as IMatrixTimelineItem | undefined)
          ?.avatarUrl,
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

  /** First page: from live timeline when fromToken is null, otherwise older page. */
  async getRoomMessages(
    roomId: string,
    beforeTS: number | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: number | null }> {
    const { events, firstTS } = await this.layer.getRoomMessages(roomId, beforeTS, limit);
    console.time(`[MatrixTimelineService] mapRepoEventsToMessages(${roomId})`);
    const messages = await this.mapRepoEventsToMessages(events);
    console.timeEnd(`[MatrixTimelineService] mapRepoEventsToMessages(${roomId})`);
    return { messages, nextBatch: firstTS };
  }

  clearRoomPaginationTokens(roomId: string) {
    this.layer.clearRoom(roomId);
  }

  /* ---------------- Mapping helpers ---------------- */

  private async mapRepoEventsToMessages(events: RepoEvent[]): Promise<MatrixMessage[]> {
    const currentUserId = this.layer.getCurrentUserId() ?? '';
    const msgs: MatrixMessage[] = [];
    const resolvers: Array<Promise<void>> = [];
    for (const re of events.filter(
      (re) => re.type === EventType.RoomMessage || re.type === 'm.room.encrypted'
    )) {
      // Try to ensure we have decrypted content by consulting the SDK event if available
      let effectiveType = re.type;
      let effectiveContent: any = re.content;
      // TODO: wtf is this
      // try {
      //   const c = this.client;
      //   const room = c?.getRoom(re.roomId!);
      //   const live = room?.getLiveTimeline?.();
      //   const sdkEv = live?.getEvents?.().find((e: any) => e.getId?.() === re.eventId);
      //   if (sdkEv) {
      //     await c?.decryptEventIfNeeded?.(sdkEv);
      //     effectiveType = sdkEv.getType?.() || effectiveType;
      //     effectiveContent = sdkEv.getContent?.() || effectiveContent;
      //   }
      // } catch {}

      console.time(`[MatrixTimelineService] repoEventToPreview(${re.eventId})`);
      const { description } = this.repoEventToPreview({
        ...re,
        type: effectiveType,
        content: effectiveContent,
      } as RepoEvent);
      const isSelf = re.sender === currentUserId;
      // Prefer cached display name from store, then SDK membership, else MXID
      let senderDisplayName = (await this.layer.getUserDisplayName(re.sender)) || re.sender;
      if (!senderDisplayName) senderDisplayName = re.sender;
      const msgtype = effectiveContent?.msgtype;
      console.timeEnd(`[MatrixTimelineService] repoEventToPreview(${re.eventId})`);

      const msg: MatrixMessage = {
        id: re.eventId,
        sender: re.sender || 'unknown sender',
        senderDisplayName, // Assign display name
        senderAvatarUrl: undefined,
        description,
        timestamp: re.originServerTs || 0,
        isSelf,
        msgtype,
      };

      // Resolve sender avatar via AvatarService and assign onto msg
      try {
        const p = this.avatars
          .resolveUserAvatar(re.sender, { w: 32, h: 32, method: 'crop' })
          .then((url) => {
            if (url) msg.senderAvatarUrl = url;
          })
          .catch(() => {});
        resolvers.push(p);
      } catch {}

      console.time(`[MatrixTimelineService] resolveImage(${re.eventId})`);
      if (msgtype === matrixSdk.MsgType.Image) {
        const content = effectiveContent as ImageContent;
        msg.mxcUrl = content.file?.url ?? content.url;
        const p = this.mediaResolver
          .resolveImage(content)
          .then((blobUrl) => {
            if (blobUrl) msg.imageUrl = blobUrl;
            console.timeEnd(`[MatrixTimelineService] resolveImage(${re.eventId})`);
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
    this.avatars.clear();
  }

  /** Create a human preview from RepoEvent content (works for decrypted encrypted). */
  private repoEventToPreview(re: RepoEvent): { description: string } {
    let c = re.content;
    // Fallback: try to decrypt via SDK if content doesn't look like a message
    if (!c?.body && re.type === 'm.room.encrypted') {
      // TODO: wtf is this
      // try {
      //   const cli = this.client;
      //   const room = cli?.getRoom(re.roomId!);
      //   const live = room?.getLiveTimeline?.();
      //   const sdkEv = live?.getEvents?.().find((e: any) => e.getId?.() === re.eventId);
      //   if (sdkEv) {
      //     // Fire and forget; if it decrypts, content may already be clear
      //     try {
      //       cli?.decryptEventIfNeeded?.(sdkEv);
      //     } catch {}
      //     c = sdkEv.getContent?.() || c;
      //   }
      // } catch {}
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
        return { description: `${re.sender} reacted with ${key}` };
      }
    }
    if (relates?.rel_type === 'm.reference') {
      return { description: 'Replied to a message' };
    }
    return { description: 'This message could not be decrypted.' };
  }

  // removed avatar helpers: now handled by AvatarService
}
