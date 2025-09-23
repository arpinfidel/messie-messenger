import * as matrixSdk from 'matrix-js-sdk';
import { MatrixEvent, MatrixEventEvent } from 'matrix-js-sdk/lib/models/event';
import type { RepoEvent } from './TimelineRepository';
import { Direction } from 'matrix-js-sdk/lib/models/event-timeline';
import { IndexedDbCache } from './IndexedDbCache';
import { AvatarResolver, type ResolveResult } from './AvatarResolver';
import { MediaResolver } from './MediaResolver';
import type { DbMember, DbRoom, DbUser } from './idb/constants';
import type { ImageContent } from 'matrix-js-sdk/lib/types';

type RepoEventListener = (ev: RepoEvent, room: matrixSdk.Room, meta?: { isLive?: boolean }) => void;

class RepoEventEmitter {
  private listeners = new Set<RepoEventListener>();

  on(listener: RepoEventListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(ev: RepoEvent, room: matrixSdk.Room, meta?: { isLive?: boolean }) {
    for (const l of this.listeners) {
      try {
        l(ev, room, meta);
      } catch (err) {
        console.error('[MatrixDataLayer] RepoEvent listener failed', err);
      }
    }
  }
}

type UnreadChangeListener = (roomId: string, unread: number) => void;

class UnreadEventEmitter {
  private listeners = new Set<UnreadChangeListener>();
  on(listener: UnreadChangeListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
  emit(roomId: string, unread: number) {
    for (const l of this.listeners) {
      try {
        l(roomId, unread);
      } catch (err) {
        console.error('[MatrixDataLayer] UnreadEvent listener failed', err);
      }
    }
  }
}

type ReadReceiptListener = (roomId: string, eventId: string, userId: string) => void;

class ReadReceiptEventEmitter {
  private listeners = new Set<ReadReceiptListener>();

  on(listener: ReadReceiptListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(roomId: string, eventId: string, userId: string) {
    for (const l of this.listeners) {
      try {
        l(roomId, eventId, userId);
      } catch (err) {
        console.error('[MatrixDataLayer] ReadReceipt listener failed', err);
      }
    }
  }
}

export interface MatrixDataLayerOptions {
  getClient: () => matrixSdk.MatrixClient | null;
  shouldIncludeEvent?: (ev: matrixSdk.MatrixEvent) => boolean;
  tryDecryptEvent?: (ev: matrixSdk.MatrixEvent) => Promise<void> | void;
  waitForPrepared: () => Promise<void>;
  pageSize?: number; // default 20
}

/**
 * Data layer that bridges the Matrix SDK with lightweight IndexedDB
 * persistence. Sliding sync remains the source of truth for timelines, while
 * IndexedDB keeps avatars/media and room summaries for faster cold starts.
 */
export class MatrixDataLayer {
  private pageSize: number;
  private db = new IndexedDbCache();
  private currentUserId: string | null = null;
  private currentUserDisplayName: string | null = null;

  private inMemoryRooms = new Map<string, DbRoom>();

  private avatarResolver: AvatarResolver;
  private mediaResolver: MediaResolver;
  private repoEventEmitter = new RepoEventEmitter();
  private unreadEventEmitter = new UnreadEventEmitter();
  private readReceiptEmitter = new ReadReceiptEventEmitter();

  constructor(private readonly opts: MatrixDataLayerOptions) {
    this.pageSize = opts.pageSize ?? 20;
    this.avatarResolver = new AvatarResolver(opts.getClient, {
      maxMemEntries: 200,
      maxDbEntries: 200,
    });
    this.mediaResolver = new MediaResolver(opts.getClient, { maxEntries: 200 });
  }

  async init(): Promise<MatrixDataLayer> {
    await this.db.init();
    const [currentUserId, currentUserDisplayName] = await Promise.all([
      this.db.getMeta<string>('currentUserId'),
      this.db.getMeta<string>('currentUserDisplayName'),
    ]);
    if (currentUserId) this.currentUserId = currentUserId;
    if (currentUserDisplayName) this.currentUserDisplayName = currentUserDisplayName;
    try {
      const persistedRooms = await this.db.rooms.getAll();
      for (const room of persistedRooms) {
        this.inMemoryRooms.set(room.id, room);
      }
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to load cached rooms', err);
    }
    this.bind();
    return this;
  }

  onRepoEvent(
    listener: (ev: RepoEvent, room: matrixSdk.Room, meta?: { isLive?: boolean }) => void
  ): () => void {
    return this.repoEventEmitter.on(listener);
  }

  onUnreadChange(listener: UnreadChangeListener): () => void {
    return this.unreadEventEmitter.on(listener);
  }

  onReadReceipt(listener: ReadReceiptListener): () => void {
    return this.readReceiptEmitter.on(listener);
  }

  /**
   * Compute the minimum read timestamp among other joined members in a room.
   * Returns 0 if the client/room is not available yet.
   */
  async getMinOtherReadTs(roomId: string): Promise<number> {
    try {
      const self = this.currentUserId;
      const members = await this.getRoomMembers(roomId);
      console.log('[MatrixDataLayer] getMinOtherReadTs', roomId, members, self);
      let min = Infinity;
      for (const m of members) {
        if (!m || m.userId === self) continue;
        if (m.membership && m.membership !== 'join') continue;
        const ts = m.lastReadTs || 0;
        if (ts < min) min = ts;
      }
      if (min === Infinity) return 0;
      return min;
    } catch (e) {
      console.warn('[MatrixDataLayer] getMinOtherReadTs failed', e);
      return 0;
    }
  }

  bind(): void {
    const c = this.client;
    if (!c) return;
    this.seedRoomsFromClient(c);
    this.handleEvents(c);
    this.handleUnreadNotifications(c);
    this.handleReceipts(c);
  }

  private get client(): matrixSdk.MatrixClient | null {
    return this.opts.getClient();
  }

  private getUnreadFromRoom(room: matrixSdk.Room): number {
    try {
      return (
        room.getUnreadNotificationCount(
          (matrixSdk as any).NotificationCountType?.Total ?? undefined
        ) as number
      ) ?? 0;
    } catch {
      return 0;
    }
  }

  private upsertInMemoryRoom(
    room: matrixSdk.Room,
    overrides: Partial<DbRoom> = {},
    persist = false
  ): void {
    const existing = this.inMemoryRooms.get(room.roomId);
    const baseTs = Math.max(existing?.latestTimestamp ?? 0, room.getLastActiveTimestamp() ?? 0);
    const latestTimestamp = overrides.latestTimestamp ?? baseTs;
    const unreadCount = overrides.unreadCount ?? existing?.unreadCount ?? this.getUnreadFromRoom(room);
    const avatarMxcUrl =
      overrides.avatarMxcUrl ?? existing?.avatarMxcUrl ?? room.getMxcAvatarUrl() ?? undefined;
    const name = overrides.name ?? existing?.name ?? room.name ?? room.roomId;
    const hasLastEventOverride = Object.prototype.hasOwnProperty.call(overrides, 'lastEvent');
    const lastEvent = hasLastEventOverride
      ? overrides.lastEvent ?? null
      : existing?.lastEvent ?? null;

    const updated: DbRoom = {
      id: room.roomId,
      name,
      latestTimestamp,
      avatarMxcUrl,
      unreadCount,
      lastEvent,
    };
    this.inMemoryRooms.set(room.roomId, updated);
    if (persist) {
      void this.db.rooms.put(updated).catch((err) => {
        console.warn('[MatrixDataLayer] Failed to persist room summary', err);
      });
    }
  }

  private seedRoomsFromClient(client: matrixSdk.MatrixClient): void {
    for (const room of client.getRooms() || []) {
      this.upsertInMemoryRoom(room);
    }
  }

  // ------------------------------------------------------------------
  // Current user helpers
  // ------------------------------------------------------------------

  setCurrentUser(userId: string, displayName?: string | null) {
    this.currentUserId = userId;
    this.db.setMeta('currentUserId', userId).catch((err) => {
      console.warn('[MatrixDataLayer] Failed to persist currentUserId', err);
    });
    if (displayName) {
      this.currentUserDisplayName = displayName || null;
      this.db.setMeta('currentUserDisplayName', displayName).catch((err) => {
        console.warn('[MatrixDataLayer] Failed to persist currentUserDisplayName', err);
      });
    }
  }

  getCurrentUserId(): string | null {
    return this.currentUserId;
  }

  getCurrentUserDisplayName(): string | null {
    return this.currentUserDisplayName || this.currentUserId;
  }

  // ------------------------------------------------------------------
  // Basic queries (rooms, users, members)
  // ------------------------------------------------------------------

  async getRooms() {
    const client = this.client;
    if (client) {
      this.seedRoomsFromClient(client);
    }
    return Array.from(this.inMemoryRooms.values());
  }

  async getRoom(roomId: string) {
    const client = this.client;
    const room = client?.getRoom(roomId);
    if (room) this.upsertInMemoryRoom(room);
    return this.inMemoryRooms.get(roomId);
  }

  async markRoomAsRead(roomId: string) {
    const client = this.client;
    const room = client?.getRoom(roomId);
    if (room) {
      this.upsertInMemoryRoom(room, { unreadCount: 0 }, true);
    } else {
      const existing = this.inMemoryRooms.get(roomId);
      if (existing) {
        const updated: DbRoom = { ...existing, unreadCount: 0 };
        this.inMemoryRooms.set(roomId, updated);
        void this.db.rooms.put(updated).catch((err) => {
          console.warn('[MatrixDataLayer] Failed to persist read state', err);
        });
      }
    }
    this.unreadEventEmitter.emit(roomId, 0);

    // Try to sync read markers to the server
    try {
      const client = this.client;
      const room = client?.getRoom(roomId);
      const live = room?.getLiveTimeline();
      const events = live?.getEvents() || [];
      // Prefer the most recent message-like event with an ID
      const lastEvent = [...events].reverse().find(
        (e) =>
          !!e.getId() &&
          this.isMessageLike({
            eventId: e.getId() || '',
            roomId: roomId,
            type: e.getType(),
            sender: e.getSender() || '',
            originServerTs: e.getTs(),
            content: e.getContent(),
            unsigned: e.getUnsigned(),
          } as any)
      );

      if (client && room && lastEvent && lastEvent.getId()) {
        // Update both fully-read marker and read receipt to the same event
        await client.setRoomReadMarkers(roomId, lastEvent.getId()!, lastEvent);
      }
    } catch (err) {
      // Non-fatal: keep local unread at 0 and let future syncs reconcile
      console.warn('[MatrixDataLayer] Failed to sync read markers', err);
    }
  }

  async getRoomMembers(roomId: string) {
    await this.opts.waitForPrepared();
    const client = this.client;
    if (!client) {
      console.error(`[MatrixDataLayer] getRoomMembers(${roomId}) → Matrix client not available`);
      return [];
    }
    const room = client.getRoom(roomId);
    if (!room) {
      console.warn(`[MatrixDataLayer] getRoomMembers(${roomId}) → room not found`);
      return [];
    }

    const members = room.getMembers() || [];
    const result: DbMember[] = members.map((member) => {
      const readUpTo = room.getEventReadUpTo?.(member.userId) as string | undefined;
      const ts = readUpTo ? room.findEventById(readUpTo)?.getTs?.() ?? 0 : 0;
      return {
        key: `${roomId}|${member.userId}`,
        roomId,
        userId: member.userId,
        displayName: member.rawDisplayName || member.name,
        avatarUrl: member.getMxcAvatarUrl() || undefined,
        membership: member.membership,
        lastReadTs: ts || 0,
      };
    });
    return result;
  }

  async getUser(userId: string) {
    const u = this.db.users.get(userId);
    if (u) return u;
    // Try to fetch from SDK if not in DB
    const c = this.client;
    if (!c) return undefined;
    const m = c.getUser(userId);
    if (!m) return undefined;
    const display = m.displayName || m.rawDisplayName;
    const mxc = m.avatarUrl;
    const user: DbUser = { userId, displayName: display, avatarMxcUrl: mxc };
    try {
      await this.db.users.put(user);
    } catch {
      // ignore
    }
    return user;
  }

  async getUserDisplayName(userId: string): Promise<string | undefined> {
    const u = await this.getUser(userId);
    return u?.displayName || undefined;
  }

  // ------------------------------------------------------------------
  // SDK <-> DB bridges
  // ------------------------------------------------------------------

  /** Convert SDK event to RepoEvent with optional decryption + filter. */
  private async toRepoEvent(ev: matrixSdk.MatrixEvent, index?: number): Promise<RepoEvent | null> {
    if (this.opts.shouldIncludeEvent && !this.opts.shouldIncludeEvent(ev)) return null;
    if (this.opts.tryDecryptEvent) {
      await this.opts.tryDecryptEvent(ev);
    }
    const idx = index ?? (ev as any).mxIndex ?? 0;
    return {
      eventId: ev.getId() ?? '',
      roomId: ev.getRoomId() ?? '',
      type: ev.getType(),
      sender: ev.getSender() ?? '',
      originServerTs: ev.getTs(),
      index: idx,
      content: ev.getContent(),
      unsigned: ev.getUnsigned(),
    };
  }

  async getLatestCachedMessages(
    roomId: string,
    beforeIndex: number | null,
    limit = this.pageSize
  ): Promise<{ events: RepoEvent[]; firstIndex: number | null }> {
    if (beforeIndex == null && limit > 0) {
      const cached = this.inMemoryRooms.get(roomId)?.lastEvent;
      if (cached) {
        return { events: [cached], firstIndex: cached.index ?? null };
      }
    }
    return this.getRoomEventsFromSdk(roomId, beforeIndex, limit);
  }

  /**
   * Fetch a paginated set of events for a room. Uses cached events first and
   * falls back to the Matrix SDK when more events are needed. Always paginate
   * by custom monotonic index. If events from DB are insufficient, fetch more
   * from the SDK and return the smallest index as the next token.
   */
  async getRoomEvents(
    roomId: string,
    beforeIndex: number | null,
    limit = this.pageSize,
    _dbOnly = false
  ): Promise<{ events: RepoEvent[]; firstIndex: number | null }> {
    return this.getRoomEventsFromSdk(roomId, beforeIndex, limit);
  }

  private async getRoomEventsFromSdk(
    roomId: string,
    beforeIndex: number | null,
    limit: number
  ): Promise<{ events: RepoEvent[]; firstIndex: number | null }> {
    await this.opts.waitForPrepared();
    const client = this.client;
    if (!client) {
      return { events: [], firstIndex: beforeIndex };
    }
    const room = client.getRoom(roomId);
    if (!room) {
      return { events: [], firstIndex: beforeIndex };
    }

    const timeline = room.getLiveTimeline();
    const collectEvents = () =>
      timeline
        .getEvents()
        .filter((ev) => !!ev.getId())
        .filter((ev) => {
          const t = ev.getType();
          return t === 'm.room.message' || t === 'm.room.encrypted';
        });

    let events = collectEvents();
    const filterByIndex = (evs: MatrixEvent[]) => {
      if (beforeIndex == null) return evs;
      return evs.filter((ev) => (ev.getTs() || 0) < beforeIndex);
    };

    events = filterByIndex(events);

    while (events.length < limit) {
      const token = timeline.getPaginationToken(Direction.Backward);
      if (!token) break;
      const more = await client.paginateEventTimeline(timeline, {
        backwards: true,
        limit: limit * 2,
      });
      if (!more) break;
      events = filterByIndex(collectEvents());
    }

    const selected = events.slice(-limit);
    const repoEvents: RepoEvent[] = [];
    for (const ev of selected) {
      const repo = await this.toRepoEvent(ev);
      if (!repo) continue;
      const ts = ev.getTs() || Date.now();
      repo.index = ts;
      repoEvents.push(repo);
    }
    repoEvents.sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
    const firstIndex = repoEvents.length ? repoEvents[0].index ?? null : beforeIndex;
    return { events: repoEvents, firstIndex: firstIndex ?? null };
  }
  private handleEvents(client: matrixSdk.MatrixClient) {
    client.on(
      matrixSdk.RoomEvent.Timeline,
      async (
        ev: MatrixEvent,
        room: matrixSdk.Room | undefined,
        toStartOfTimeline: boolean | undefined,
        removed: boolean,
        data: matrixSdk.IRoomTimelineData
      ) => {
        if (!room) {
          console.warn('[MatrixDataLayer] timeline event without room?');
          return;
        }
        let re = await this.toRepoEvent(ev);
        if (!re) return;

        if (!this.isMessageLike(re)) {
          console.debug('[MatrixDataLayer] ignoring non-message timeline event', re);
          return;
        }

        const eventIndex = ev.getTs() || Date.now();
        (ev as any).mxIndex = eventIndex;
        re.index = eventIndex;

        await client.decryptEventIfNeeded(ev);

        // Only increment unread for true live events; avoid double-counting
        // during initial sync or backfill where SDK replays timeline history.
        const syncState = (client as any)?.getSyncState?.();
        const isTrueLive = data?.liveEvent === true && syncState === 'SYNCING';

        const latestTimestamp = Math.max(
          ev.getTs(),
          this.inMemoryRooms.get(room.roomId)?.latestTimestamp ?? 0
        );
        this.upsertInMemoryRoom(room, { latestTimestamp, lastEvent: re }, true);

        // Emit repo event; include whether this was a true live event
        this.repoEventEmitter.emit(re, room, { isLive: isTrueLive });

        const onDecrypted = async () => {
          if (ev.isDecryptionFailure()) return;
          try {
            const updated = await this.toRepoEvent(ev, eventIndex);
            if (updated) {
              this.upsertInMemoryRoom(room, { lastEvent: updated }, true);
              this.repoEventEmitter.emit(updated, room, { isLive: false });
            }
          } finally {
            try {
              ev.off(MatrixEventEvent.Decrypted, onDecrypted);
            } catch (err) {
              console.warn('[MatrixDataLayer] Failed to detach decrypted listener', err);
            }
          }
        };
        ev.on(MatrixEventEvent.Decrypted, onDecrypted);
      }
    );
  }

  /**
   * Listen for unread notification changes from the SDK and keep our DB in sync.
   * This ensures cross-device read state updates (e.g., when another device
   * reads a room) are reflected locally.
   */
  private handleUnreadNotifications(client: matrixSdk.MatrixClient) {
    const attach = (room: matrixSdk.Room) => {
      try {
        const writeUnread = async () => {
          try {
            const total = (
              room.getUnreadNotificationCount(
                (matrixSdk as any).NotificationCountType?.Total ?? undefined
              ) as number
            ) ?? 0;
            this.upsertInMemoryRoom(room, { unreadCount: total ?? 0 }, true);
            this.unreadEventEmitter.emit(room.roomId, total ?? 0);
          } catch (err) {
            console.warn('[MatrixDataLayer] Failed to update unread from SDK', err);
          }
        };

        // Listen for future changes
        room.on(matrixSdk.RoomEvent.UnreadNotifications, writeUnread);
        // Seed initial value so first login reflects server state
        this.upsertInMemoryRoom(room);
        void writeUnread();
      } catch (err) {
        console.error('[MatrixDataLayer] Failed to attach unread listener', err);
      }
    };

    // Attach to existing rooms
    for (const r of client.getRooms() || []) attach(r);

    // Attach to new rooms as they are discovered
    client.on((matrixSdk as any).ClientEvent?.Room || 'Room', (room: matrixSdk.Room) =>
      attach(room)
    );
  }

  private async handleReceipts(client: matrixSdk.MatrixClient) {
    client.on(matrixSdk.RoomEvent.Receipt, async (ev, room) => {
      const content = ev.getContent() as any;
      if (!room || !content) return;

      for (const [eventId, receiptTypes] of Object.entries<any>(content)) {
        const reads = receiptTypes?.['m.read'];
        if (!reads) continue;
        for (const [userId, meta] of Object.entries<any>(reads)) {
          this.readReceiptEmitter.emit(room.roomId, eventId, userId);
        }
      }
    });
  }

  /** Update a room's unread count in the local DB. */
  async setRoomUnreadCount(roomId: string, count: number): Promise<void> {
    const room = this.client?.getRoom(roomId);
    if (room) {
      this.upsertInMemoryRoom(room, { unreadCount: count }, true);
    } else {
      const existing = this.inMemoryRooms.get(roomId);
      if (!existing) return;
      const updated: DbRoom = { ...existing, unreadCount: count };
      this.inMemoryRooms.set(roomId, updated);
      void this.db.rooms.put(updated).catch((err) => {
        console.warn('[MatrixDataLayer] Failed to persist unread count', err);
      });
    }
    this.unreadEventEmitter.emit(roomId, count);
  }

  /**
   * Sync a single room's metadata, members and persist last-read timestamps for members.
   * Safe to call opportunistically; runs client lookups and writes snapshots into IDB.
   */
  async syncRoom(roomId: string): Promise<void> {
    try {
      await this.opts.waitForPrepared();
      const client = this.client;
      if (!client) return;
      const room = client.getRoom(roomId);
      if (!room) return;
      const latestTimestamp = room.getLastActiveTimestamp() ?? Date.now();
      this.upsertInMemoryRoom(room, { latestTimestamp }, true);
    } catch (err) {
      console.warn('[MatrixDataLayer] syncRoom failed', err);
    }
  }

  // ------------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------------

  isMessageLike(ev: RepoEvent): boolean {
    const t = ev.type;
    return t === 'm.room.message' || t === 'm.room.encrypted';
  }

  // ------------------------------------------------------------------
  async resolveAvatarMxc(
    mxc: string,
    dims: { w: number; h: number; method: 'crop' },
    tag?: string
  ): Promise<ResolveResult> {
    // try db
    const key = this.avatarResolver.key(mxc, dims);
    const cached = await this.db.getMedia(key);
    if (cached) {
      if (cached.status === 200) {
        const objectUrl = URL.createObjectURL(cached.blob);
        const url = this.tagUrl(objectUrl, this.buildAvatarFragment(tag, mxc, 'cache'));
        return { status: 200, url, bytes: cached.bytes, mime: cached.mime, blob: cached.blob, objectUrl };
      }
      return { status: cached.status };
    }

    // try resolver
    const result = await this.avatarResolver.resolve(mxc, dims);

    if (result.status === 200 && result.blob) {
      try {
        await this.db.putMedia({
          status: 200,
          key,
          ts: Date.now(),
          bytes: result.bytes ?? result.blob.size,
          mime: result.mime ?? (result.blob.type || 'image/png'),
          blob: result.blob,
        });
      } catch (err) {
        console.warn('[MatrixDataLayer] Failed to cache avatar in IDB', err);
      }
      const objectUrl = result.objectUrl ?? URL.createObjectURL(result.blob);
      const url = this.tagUrl(objectUrl, this.buildAvatarFragment(tag, mxc, 'fresh'));
      return { ...result, url, objectUrl };
    }

    if (result.status >= 400) {
      try {
        await this.db.putMedia({
          status: result.status,
          key,
          ts: Date.now(),
          bytes: 0,
          mime: 'application/octet-stream',
          blob: new Blob(),
        });
      } catch (err) {
        console.warn('[MatrixDataLayer] Failed to record avatar error in IDB', err);
      }
    }

    return result;
  }

  async invalidateAvatarMxc(
    mxc: string,
    dims: { w: number; h: number; method: 'crop' }
  ): Promise<void> {
    try {
      const key = this.avatarResolver.key(mxc, dims);
      await this.db.deleteMedia(key);
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to invalidate avatar cache', mxc, err);
    }
  }

  private tagUrl(objectUrl: string, fragment: string): string {
    try {
      const url = new URL(objectUrl);
      url.hash = fragment;
      return url.toString();
    } catch {
      return `${objectUrl}#${fragment}`;
    }
  }

  private buildAvatarFragment(tag: string | undefined, mxc: string, source: 'cache' | 'fresh'): string {
    const parts: string[] = [];
    if (tag) parts.push(tag);
    parts.push(`src=${source}`);
    parts.push(`mxc=${encodeURIComponent(mxc)}`);
    return parts.join('|');
  }

  async resolveImage(
    img: ImageContent,
    dims = { w: 1024, h: 1024, method: 'scale' as const }
  ): Promise<string | undefined> {
    // try db
    const key = this.mediaResolver.computeKeyForImage(img, dims);
    if (key) {
      const cached = await this.db.getMedia(key);
      if (cached) {
        const url = URL.createObjectURL(cached.blob);
        console.log('[MatrixDataLayer] resolveImage cache hit', key, url);
        return url;
      }
    }
    console.log('[MatrixDataLayer] resolveImage cache miss', key);

    // try resolver
    const url = await this.mediaResolver.resolveImage(img, dims);
    if (!url) return undefined;

    // save
    try {
      const resp = await fetch(url);
      if (resp.ok) {
        const blob = await resp.blob();
        if (key) {
          await this.db.putMedia({
            status: 200,
            key,
            ts: Date.now(),
            bytes: blob.size,
            mime: blob.type || 'image/*',
            blob,
          });
        }
      }
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to cache image in IDB', err);
    }

    return url;
  }

  async resolveFile(fileContent: any): Promise<string | undefined> {
    const key = fileContent.file?.url || fileContent.url;
    if (key) {
      const cached = await this.db.getMedia(key);
      if (cached) {
        const url = URL.createObjectURL(cached.blob);
        console.log('[MatrixDataLayer] resolveFile cache hit', key, url);
        return url;
      }
    }
    console.log('[MatrixDataLayer] resolveFile cache miss', key);

    const url = await this.mediaResolver.resolveFile(fileContent);
    if (!url) return undefined;

    try {
      const resp = await fetch(url);
      if (resp.ok && key) {
        const blob = await resp.blob();
        await this.db.putMedia({
          status: 200,
          key,
          ts: Date.now(),
          bytes: blob.size,
          mime: blob.type || fileContent.info?.mimetype || 'application/octet-stream',
          blob,
        });
      }
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to cache file in IDB', err);
    }

    return url;
  }
}
