import * as matrixSdk from 'matrix-js-sdk';
import { EventType, MatrixEvent, Room } from 'matrix-js-sdk';
import { writable, type Writable, get } from 'svelte/store';

import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixDataStore } from './core/MatrixDataStore';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import type { ImageContent } from 'matrix-js-sdk/lib/@types/media';
import { MediaResolver } from './core/MediaResolver';
import { AvatarResolver } from './core/AvatarResolver';
import { IndexedDbCache } from './core/IndexedDbCache';

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
  private avatarResolver = new AvatarResolver(() => this.client, {
    maxMemEntries: 200,
    maxDbEntries: 200,
  });
  private compositeAvatarCache = new Map<string, string>(); // key: roomId|mxc1|mxc2 -> blob URL
  private imgDb = new IndexedDbCache(); // persist composed avatars in IDB
  private readonly maxRooms = 30; // limit room list to most recent N

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
  async fetchAndSetTimelineItems(preferCacheOnly = false): Promise<void> {
    // Build timeline from whatever is available. If the client isn't started yet,
    // we skip fetching from live timelines and just use cached data.
    if (this.listRefreshInFlight) return;

    this.listRefreshInFlight = true;
    try {
      const rooms = this.store.getRooms();
      const canFetchInitial = !preferCacheOnly && this.ctx.isStarted();
      // Sort rooms by latest activity and keep only top N
      const limitedRooms = rooms
        .slice()
        .sort((a, b) => (b.latestTimestamp ?? 0) - (a.latestTimestamp ?? 0))
        .slice(0, this.maxRooms);
      

      // If client is started, ensure at least one event via live timeline; otherwise rely on cache.
      if (canFetchInitial) {
        for (const r of limitedRooms) {
          if (!this.store.getLatestEvent(r.id)) {
            try { await this.layer.fetchInitial(r.id, 1); } catch {}
          }
        }
      }

      const items: IMatrixTimelineItem[] = [];
      const currentItems = get(this._timelineItems) as IMatrixTimelineItem[];
      // Build items quickly without awaiting avatar resolution to avoid UI delay
      for (const room of limitedRooms) {
        const last = this.store.getLatestEvent(room.id);
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
            const url = await this.resolveRoomAvatar(
              room.id,
              room.avatarUrl as string | null | undefined
            );
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
    } finally {
      this.listRefreshInFlight = false;
    }
  }

  scheduleTimelineRefresh(delay = 200) {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(async () => {
      this.refreshTimer = null;
      if (this.listRefreshInFlight) return;

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
      const roomMxc = room.getMxcAvatarUrl();
      avatarUrl = await this.resolveRoomAvatar(room.roomId, roomMxc || undefined);
    } catch {}

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
        const c = this.client;
        const room = c?.getRoom(re.roomId!);
        const live = room?.getLiveTimeline?.();
        const sdkEv = live?.getEvents?.().find((e: any) => e.getId?.() === re.eventId);
        if (sdkEv) {
          await c?.decryptEventIfNeeded?.(sdkEv);
          effectiveType = sdkEv.getType?.() || effectiveType;
          effectiveContent = sdkEv.getContent?.() || effectiveContent;
        }
      } catch {}

      const { description } = this.repoEventToPreview({
        ...re,
        type: effectiveType,
        content: effectiveContent,
      } as RepoEvent);
      const isSelf = re.sender === currentUserId;
      // Prefer cached display name from store, then SDK membership, else MXID
      let senderDisplayName = this.store.getUserDisplayName(re.sender) || re.sender;
      if (!senderDisplayName) senderDisplayName = re.sender;
      if (senderDisplayName === re.sender) {
        try {
          const c = this.client;
          const room = c?.getRoom(re.roomId!);
          const member = room?.getMember(re.sender);
          if (member) senderDisplayName = member.rawDisplayName || member.name || re.sender;
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
            .then((url) => {
              if (url) msg.senderAvatarUrl = url;
            })
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
    for (const [, url] of this.compositeAvatarCache) {
      try {
        URL.revokeObjectURL(url);
      } catch {}
    }
    this.compositeAvatarCache.clear();
  }

  /** Create a human preview from RepoEvent content (works for decrypted encrypted). */
  private repoEventToPreview(re: RepoEvent): { description: string } {
    let c: any = re.content;
    // Fallback: try to decrypt via SDK if content doesn't look like a message
    if (!c?.body && re.type === 'm.room.encrypted') {
      try {
        const cli = this.client;
        const room = cli?.getRoom(re.roomId!);
        const live = room?.getLiveTimeline?.();
        const sdkEv = live?.getEvents?.().find((e: any) => e.getId?.() === re.eventId);
        if (sdkEv) {
          // Fire and forget; if it decrypts, content may already be clear
          try {
            cli?.decryptEventIfNeeded?.(sdkEv);
          } catch {}
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

  // ---- Avatar helpers ----
  private async resolveRoomAvatar(
    roomId: string,
    roomMxc?: string | null
  ): Promise<string | undefined> {
    // If room has its own avatar, prefer it.
    if (roomMxc) {
      const url = await this.avatarResolver.resolve(roomMxc, { w: 64, h: 64, method: 'crop' });
      if (url) return url;
    }
    // Fallback: top 3 joined member avatars (prefer non-self), compose if multiple exist
    const members = this.store.getRoomMembers(roomId) || [];
    const currentUserId = this.store.getCurrentUserId();
    const sorted = members
      .filter((m) => (m.membership || 'join') === 'join')
      .sort((a, b) => {
        const pref = (a.userId === currentUserId ? 1 : 0) - (b.userId === currentUserId ? 1 : 0);
        if (pref !== 0) return pref;
        return a.userId.localeCompare(b.userId);
      });
    const mxcs: string[] = [];
    for (const m of sorted) {
      const mxc = this.store.getUser(m.userId)?.avatarUrl || undefined;
      if (mxc && !mxcs.includes(mxc)) mxcs.push(mxc);
      if (mxcs.length >= 3) break;
    }
    if (mxcs.length === 0) return undefined;
    if (mxcs.length === 1)
      return (
        (await this.avatarResolver.resolve(mxcs[0], { w: 64, h: 64, method: 'crop' })) || undefined
      );

    // Compose N (2..3) avatars with stable random layout seeded by room+mxcs
    const key = `${roomId}|${mxcs.sort().join('|')}`;
    const cached = this.compositeAvatarCache.get(key);
    if (cached) return cached;

    // Try persistent cache for composed avatar
    const dbKey = `avatar-composite|${key}|64x64`;
    try {
      const rec = await this.imgDb.getMedia(dbKey);
      if (rec && rec.blob) {
        const url = URL.createObjectURL(rec.blob);
        this.compositeAvatarCache.set(key, url);
        return url;
      }
    } catch {}

    const urls = await Promise.all(
      mxcs.map((m) => this.avatarResolver.resolve(m, { w: 64, h: 64, method: 'crop' }))
    );
    const resolved = urls.filter((u): u is string => !!u);
    if (resolved.length === 0) return undefined;
    if (resolved.length === 1) return resolved[0];
    const composed = await this.composeBubbleAvatars(resolved.slice(0, 3), 64);
    if (composed) {
      this.compositeAvatarCache.set(key, composed.url);
      // Persist composed avatar in IDB for fast startup next time
      try {
        await this.imgDb.putMedia({
          key: dbKey,
          ts: Date.now(),
          bytes: composed.blob.size,
          mime: 'image/png',
          blob: composed.blob,
        });
        await this.imgDb.pruneMedia(200);
      } catch {}
      return composed.url;
    }
    return resolved[0];
  }

  private async composeBubbleAvatars(
    urls: string[],
    size = 64
  ): Promise<{ url: string; blob: Blob } | undefined> {
    try {
      const imgs = await Promise.all(urls.map((u) => this.loadImage(u)));
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext('2d');
      if (!ctx) return undefined;
      ctx.clearRect(0, 0, size, size);

      // Static placements that look organic and fit inside 64x64
      const n = Math.min(3, imgs.length);
      const positions: { x: number; y: number; r: number; img: HTMLImageElement }[] = [];
      if (n === 2) {
        const r = Math.floor(size * 0.32);
        positions.push({ x: Math.floor(size * 0.36), y: Math.floor(size * 0.44), r, img: imgs[0] });
        positions.push({ x: Math.floor(size * 0.64), y: Math.floor(size * 0.56), r, img: imgs[1] });
      } else {
        const r = Math.floor(size * 0.28);
        positions.push({ x: Math.floor(size * 0.34), y: Math.floor(size * 0.36), r, img: imgs[0] });
        positions.push({ x: Math.floor(size * 0.66), y: Math.floor(size * 0.4), r, img: imgs[1] });
        positions.push({ x: Math.floor(size * 0.5), y: Math.floor(size * 0.68), r, img: imgs[2] });
      }

      // Draw bubbles with thin black border
      for (const p of positions) {
        ctx.save();
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.closePath();
        ctx.clip();
        this.drawCover(ctx, p.img, p.x - p.r, p.y - p.r, p.r * 2, p.r * 2);
        ctx.restore();
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r - 0.5, 0, Math.PI * 2);
        ctx.closePath();
        ctx.lineWidth = 1;
        ctx.strokeStyle = '#000';
        ctx.stroke();
      }

      const blob: Blob | null = await new Promise((resolve) =>
        canvas.toBlob((b) => resolve(b), 'image/png')
      );
      if (!blob) return undefined;
      const url = URL.createObjectURL(blob);
      return { url, blob };
    } catch {
      return undefined;
    }
  }

  private loadImage(url: string): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => resolve(img);
      img.onerror = (e) => reject(e);
      img.src = url;
    });
  }

  private drawCover(
    ctx: CanvasRenderingContext2D,
    img: HTMLImageElement,
    dx: number,
    dy: number,
    dw: number,
    dh: number
  ) {
    // drawImage with cover behavior
    const iw = img.naturalWidth || img.width;
    const ih = img.naturalHeight || img.height;
    const targetRatio = dw / dh;
    const imgRatio = iw / ih;
    let sx = 0,
      sy = 0,
      sw = iw,
      sh = ih;
    if (imgRatio > targetRatio) {
      // Image is wider than target; crop sides
      sh = ih;
      sw = sh * targetRatio;
      sx = (iw - sw) / 2;
    } else {
      // Image is taller; crop top/bottom
      sw = iw;
      sh = sw / targetRatio;
      sy = (ih - sh) / 2;
    }
    ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
  }

  // removed seeded RNG in favor of static placement
}
