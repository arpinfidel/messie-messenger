import * as matrixSdk from 'matrix-js-sdk';
import { MatrixEvent, MatrixEventEvent, type IEvent } from 'matrix-js-sdk/lib/models/event';
import type { RepoEvent } from './TimelineRepository';
import { Direction } from 'matrix-js-sdk/lib/models/event-timeline';
import { IndexedDbCache } from './IndexedDbCache';
import { AvatarResolver } from './AvatarResolver';
import { MediaResolver } from './MediaResolver';
import type { DbUser } from './idb/constants';
import type { ImageContent } from 'matrix-js-sdk/lib/types';
import { MatrixViewModel } from '../MatrixViewModel';

type RepoEventListener = (ev: RepoEvent, room: matrixSdk.Room) => void;

class RepoEventEmitter {
  private listeners = new Set<RepoEventListener>();

  on(listener: RepoEventListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(ev: RepoEvent, room: matrixSdk.Room) {
    for (const l of this.listeners) {
      try {
        l(ev, room);
      } catch (err) {
        console.error('[MatrixDataLayer] RepoEvent listener failed', err);
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
 * Data layer that talks to the Matrix SDK and persists data directly into
 * IndexedDB. No in-memory cache is kept; consumers should query this layer for
 * all Matrix data.
 */
export class MatrixDataLayer {
  private pageSize: number;
  private db = new IndexedDbCache();
  private currentUserId: string | null = null;
  private currentUserDisplayName: string | null = null;

  private avatarResolver: AvatarResolver;
  private mediaResolver: MediaResolver;
  private repoEventEmitter = new RepoEventEmitter();

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
    this.bind();
    return this;
  }

  onRepoEvent(listener: (ev: RepoEvent, room: matrixSdk.Room) => void): () => void {
    return this.repoEventEmitter.on(listener);
  }

  bind(): void {
    const c = this.client;
    if (!c) return;
    this.handleEvents(c);
    this.handleUnreadNotifications(c);
    this.backgroundSync();
  }

  private get client(): matrixSdk.MatrixClient | null {
    return this.opts.getClient();
  }

  // ------------------------------------------------------------------
  // Current user helpers
  // ------------------------------------------------------------------

  setCurrentUser(userId: string, displayName?: string | null) {
    this.currentUserId = userId;
    this.db.setMeta('currentUserId', userId).catch(() => {});
    if (displayName) {
      this.currentUserDisplayName = displayName || null;
      this.db.setMeta('currentUserDisplayName', displayName).catch(() => {});
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
    return this.db.rooms.getAll();
  }

  async getRoom(roomId: string) {
    return this.db.rooms.get(roomId);
  }

  async markRoomAsRead(roomId: string) {
    const roomRec = await this.db.rooms.get(roomId);
    if (!roomRec) return;

    // Optimistically zero unread locally
    await this.db.rooms.put({ ...roomRec, unreadCount: 0 });

    // Try to sync read markers to the server
    try {
      const client = this.client;
      const room = client?.getRoom(roomId);
      const live = room?.getLiveTimeline();
      const events = live?.getEvents() || [];
      // Prefer the most recent message-like event with an ID
      const lastEvent = [...events]
        .reverse()
        .find((e) => !!e.getId() && this.isMessageLike({
          eventId: e.getId() || '',
          roomId: roomId,
          type: e.getType(),
          sender: e.getSender() || '',
          originServerTs: e.getTs(),
          content: e.getContent(),
          unsigned: e.getUnsigned(),
        } as any));

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
    const members = await this.db.getRoomMembers(roomId);
    if (members.length) return members;
    // Try to fetch from SDK if not in DB
    await this.opts.waitForPrepared();
    const c = this.client;
    if (!c) {
      console.error(`[MatrixDataLayer] getRoomMembers(${roomId}) → Matrix client not available`);
      return [];
    }
    const room = c.getRoom(roomId);
    if (!room) {
      console.warn(`[MatrixDataLayer] getRoomMembers(${roomId}) → room not found`);
      return [];
    }
    const m = room.getMembers();
    if (!m) {
      console.warn(`[MatrixDataLayer] getRoomMembers(${roomId}) → no members`);
    }
    const newMembers = Array.from(m);
    await this.db.setRoomMembers(roomId, newMembers);
    return newMembers;
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
  private async toRepoEvent(ev: matrixSdk.MatrixEvent): Promise<RepoEvent | null> {
    if (this.opts.shouldIncludeEvent && !this.opts.shouldIncludeEvent(ev)) return null;
    if (this.opts.tryDecryptEvent) {
      try {
        await this.opts.tryDecryptEvent(ev);
      } catch {
        /* ignore */
      }
    }
    return {
      eventId: ev.getId() ?? '',
      roomId: ev.getRoomId() ?? '',
      type: ev.getType(),
      sender: ev.getSender() ?? '',
      originServerTs: ev.getTs(),
      content: ev.getContent(),
      unsigned: ev.getUnsigned(),
    };
  }

  /** Build RepoEvent using wire type/content (encrypted if originally encrypted). */
  private toWireRepoEvent(ev: matrixSdk.MatrixEvent): RepoEvent {
    return {
      eventId: ev.getId() ?? '',
      roomId: ev.getRoomId() ?? '',
      type: (ev as MatrixEvent).getWireType?.() ?? ev.getType(),
      sender: ev.getSender() ?? '',
      originServerTs: ev.getTs(),
      content: (ev as MatrixEvent).getWireContent?.() ?? ev.getContent(),
      unsigned: ev.getUnsigned(),
    };
  }

  /**
   * Fetch a paginated set of events for a room. Uses cached events first and
   * falls back to the Matrix SDK when more events are needed. Always paginate
   * by TS. If events from DB are insufficient, fetch more from the SDK and
   * return last timestamp as the next token.
   */
  async getRoomEvents(
    roomId: string,
    beforeTs: number | null,
    limit = this.pageSize,
    dbOnly = false
  ): Promise<{ events: RepoEvent[]; firstTS: number | null }> {
    // Try to satisfy from cache first
    let events = await this.db.getEventsByRoom(roomId, limit, beforeTs ?? undefined);
    // decrypt on read (in-memory only) for any encrypted-at-rest entries
    events = await this.tryDecryptRepoEvents(roomId, events);
    if (events.length >= limit) {
      // If caller allows network/SDK, and we still have encrypted entries,
      // wait for client to be prepared and attempt decryption again before returning.
      if (!dbOnly && events.some((e) => e.type === 'm.room.encrypted')) {
        try {
          await this.opts.waitForPrepared();
        } catch {}
        events = await this.tryDecryptRepoEvents(roomId, events);
      }
      console.log(
        `[MatrixDataLayer] getRoomMessages(${roomId}) → ${events.length} events from cache`
      );
      const firstTS = events.length ? events[events.length - 1].originServerTs : (beforeTs ?? null);
      events.reverse();
      return { events, firstTS: firstTS };
    }
    if (dbOnly) {
      console.log(`[MatrixDataLayer] getRoomMessages(${roomId}) → DB only`);
      return { events, firstTS: beforeTs };
    }

    console.log(
      `[MatrixDataLayer] getRoomMessages(${roomId}) → ${events.length}, need ${limit} events from cache, need more...`
    );

    console.log(`[MatrixDataLayer] getRoomMessages(${roomId}) → waiting for SDK prepared`);
    await this.opts.waitForPrepared();
    console.log(`[MatrixDataLayer] getRoomMessages(${roomId}) → SDK prepared`);
    const c = this.client;
    if (!c) throw new Error('Matrix client not available');
    const room = c.getRoom(roomId);
    if (!room) {
      console.log(`[MatrixDataLayer] getRoomMessages(${roomId}) → room not found`);
      // Room not found
      return { events, firstTS: beforeTs };
    }

    const token = await this.db.getBackwardToken(roomId);
    let remoteToken: string | null;
    const live = room.getLiveTimeline();
    if (!token) {
      console.log(
        `[MatrixDataLayer] getRoomMessages(${roomId}) → no token, start paginating from live timeline`
      );
    } else {
      console.log(
        `[MatrixDataLayer] getRoomMessages(${roomId}) → have token, paginate from ${token}`
      );
      live.setPaginationToken(token, Direction.Backward);
    }
    const ok = await c.paginateEventTimeline(live, { backwards: true, limit: limit * 3 });
    remoteToken = room.getLiveTimeline().getPaginationToken(Direction.Backward);
    await this.db.setBackwardToken(roomId, remoteToken);

    events = await this.db.getEventsByRoom(roomId, limit, beforeTs ?? undefined);
    // decrypt on read (in-memory only)
    events = await this.tryDecryptRepoEvents(roomId, events);
    const firstTS = events.length ? events[events.length - 1].originServerTs : (beforeTs ?? null);
    events.reverse();

    return { events, firstTS };
  }

  private handleEvents(client: matrixSdk.MatrixClient) {
    client.on(
      matrixSdk.RoomEvent.Timeline,
      async (ev, room, toStartOfTimeline, removed, data: { liveEvent?: boolean } = {}) => {
      const re = await this.toRepoEvent(ev);
      if (!re) return;
      if (!room) {
        console.warn('[MatrixDataLayer] timeline event without room?');
        return;
      }

      if (!this.isMessageLike(re)) {
        console.debug('[MatrixDataLayer] ignoring non-message timeline event', re);
        return;
      }

      await client.decryptEventIfNeeded(ev);

      // Only increment unread for true live events; avoid double-counting
      // during initial sync or backfill where SDK replays timeline history.
      if (data?.liveEvent) {
        const existing = await this.db.rooms.get(room.roomId);
        const unread = existing?.unreadCount ?? 0;
        const increment = ev.getSender() === this.currentUserId ? 0 : 1;
        await this.db.rooms.put({
          id: room.roomId,
          name: room.name || room.roomId,
          latestTimestamp: ev.getTs(),
          avatarMxcUrl: room.getMxcAvatarUrl() || undefined,
          unreadCount: unread + increment,
        });
      } else {
        // Still update latestTimestamp & metadata without touching unread
        const existing = await this.db.rooms.get(room.roomId);
        await this.db.rooms.put({
          id: room.roomId,
          name: room.name || room.roomId,
          latestTimestamp: ev.getTs(),
          avatarMxcUrl: room.getMxcAvatarUrl() || undefined,
          unreadCount: existing?.unreadCount ?? 0,
        });
      }
      // Persist encrypted-at-rest: always store the wire form
      const wireRe = this.toWireRepoEvent(ev);
      await this.db.putEvents(room.roomId, [wireRe]).catch(() => {
        console.warn('[MatrixDataLayer] failed to persist timeline event', wireRe);
      });

      this.repoEventEmitter.emit(re, room);

      const onDecrypted = async () => {
        if (ev.isDecryptionFailure()) return;
        try {
          const updated = await this.toRepoEvent(ev);
          if (updated) this.repoEventEmitter.emit(updated, room);
        } finally {
          try {
            ev.off(MatrixEventEvent.Decrypted, onDecrypted);
          } catch {}
        }
      };
      try {
        ev.on(MatrixEventEvent.Decrypted, onDecrypted);
      } catch {}
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
            const total = room.getUnreadNotificationCount(
              (matrixSdk as any).NotificationCountType?.Total ?? undefined
            ) as number;
            const existing = await this.db.rooms.get(room.roomId);
            await this.db.rooms.put({
              id: room.roomId,
              name: room.name || room.roomId,
              latestTimestamp: existing?.latestTimestamp ?? room.getLastActiveTimestamp(),
              avatarMxcUrl: room.getMxcAvatarUrl() || existing?.avatarMxcUrl,
              unreadCount: total ?? 0,
            });
          } catch (err) {
            console.warn('[MatrixDataLayer] Failed to update unread from SDK', err);
          }
        };

        // Listen for future changes
        room.on(matrixSdk.RoomEvent.UnreadNotifications, writeUnread);
        // Seed initial value so first login reflects server state
        void writeUnread();
      } catch {}
    };

    // Attach to existing rooms
    try {
      for (const r of client.getRooms() || []) attach(r);
    } catch {}

    // Attach to new rooms as they are discovered
    try {
      client.on((matrixSdk as any).ClientEvent?.Room || 'Room', (room: matrixSdk.Room) => attach(room));
    } catch {}
  }

  /** Update a room's unread count in the local DB. */
  async setRoomUnreadCount(roomId: string, count: number): Promise<void> {
    const existing = await this.db.rooms.get(roomId);
    if (!existing) return;
    await this.db.rooms.put({
      id: roomId,
      name: existing.name || roomId,
      latestTimestamp: existing.latestTimestamp ?? 0,
      avatarMxcUrl: existing.avatarMxcUrl,
      unreadCount: count,
    });
  }

  /** Attempt to decrypt RepoEvents in-memory using the SDK (no DB writes). */
  private async tryDecryptRepoEvents(roomId: string, events: RepoEvent[]): Promise<RepoEvent[]> {
    if (!events.length) return events;
    const client = this.client;
    if (!client) return events;
    const room = client.getRoom(roomId);
    if (!room) return events;
    for (let i = 0; i < events.length; i++) {
      const re = events[i];
      if (re.type !== matrixSdk.EventType.RoomMessageEncrypted) continue;
      const raw: Partial<IEvent> = {
        event_id: re.eventId,
        type: re.type,
        content: re.content,
        sender: re.sender,
        room_id: re.roomId,
        origin_server_ts: re.originServerTs,
        unsigned: re.unsigned || {},
      };
      const mev = new MatrixEvent(raw);
      await client.decryptEventIfNeeded(mev);
      if (!mev.isDecryptionFailure()) {
        events[i] = {
          eventId: re.eventId,
          roomId: re.roomId,
          type: mev.getType(),
          sender: re.sender,
          originServerTs: re.originServerTs,
          content: mev.getContent(),
          unsigned: mev.getUnsigned(),
        };
      } else {
        // If the SDK knows about this event, subscribe for future decryption and re-emit
        try {
          const sdkEv = room.findEventById(re.eventId);
          if (sdkEv) {
            const onDecrypted = async () => {
              if (sdkEv.isDecryptionFailure()) return;
              try {
                const updated = await this.toRepoEvent(sdkEv);
                if (updated) this.repoEventEmitter.emit(updated, room);
              } finally {
                try {
                  sdkEv.off(MatrixEventEvent.Decrypted, onDecrypted);
                } catch {}
              }
            };
            sdkEv.on(MatrixEventEvent.Decrypted, onDecrypted);
          }
        } catch {}
      }
    }
    return events;
  }

  async backgroundSync() {
    await this.opts.waitForPrepared();
    const client = this.client;
    if (!client) return;

    setInterval(
      () => {
        this.syncRooms();
      },
      5 * 60 * 1000
    );
    setInterval(
      () => {
        this.syncRooms(0);
      },
      30 * 60 * 1000
    );
    this.syncRooms(0);
  }

  async syncRooms(limit = 30) {
    console.log('[MatrixDataLayer] sync avatars');
    // top 30 recent rooms
    const rooms = (await this.db.rooms.getAll()).sort((r1, r2) => {
      const t1 = r1.latestTimestamp ?? 0;
      const t2 = r2.latestTimestamp ?? 0;
      return t2 - t1;
    });

    if (!this.client) return;

    if (limit === 0) limit = rooms.length;

    for (const r of rooms.slice(0, limit)) {
      const room = this.client.getRoom(r.id);
      if (!room) continue;
      const members = room.getMembers()?.filter((m) => m.membership === 'join') || [];

      const updatedMembers: {
        userId: string;
        displayName?: string;
        avatarMxcUrl?: string;
        membership?: string;
      }[] = [];

      const existing = await this.db.rooms.get(room.roomId);
      this.db.rooms.put({
        id: room.roomId,
        name: room.name || room.roomId,
        latestTimestamp: room.getLastActiveTimestamp(),
        avatarMxcUrl: room.getMxcAvatarUrl() || undefined,
        unreadCount: existing?.unreadCount ?? 0,
      });

      for (const m of members) {
        const userId = m.userId;
        const display = m.rawDisplayName || m.name;
        const mxc = m.getMxcAvatarUrl();
        updatedMembers.push({
          userId,
          displayName: display,
          avatarMxcUrl: mxc,
          membership: m.membership,
        });
      }

      this.db.setRoomMembers(room.roomId, updatedMembers);
      if (updatedMembers.length)
        await this.db.users.putMany(
          updatedMembers.map((x) => ({
            userId: x.userId,
            displayName: x.displayName,
            avatarMxcUrl: x.avatarMxcUrl,
          }))
        );
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
    dims = { w: 32, h: 32, method: 'crop' as const }
  ): Promise<string | undefined> {
    // try db
    const key = this.avatarResolver.key(mxc, dims);
    const cached = await this.db.getMedia(key);
    if (cached) {
      const url = URL.createObjectURL(cached.blob);
      return url;
    }

    // try resolver
    const url = await this.avatarResolver.resolve(mxc, dims);

    // save
    if (url) {
      try {
        const resp = await fetch(url);
        if (resp.ok) {
          const blob = await resp.blob();
          await this.db.putMedia({
            status: 200,
            key,
            ts: Date.now(),
            bytes: blob.size,
            mime: blob.type || 'image/*',
            blob,
          });
        }
      } catch {
        // ignore
      }
    }

    return url;
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
    } catch {
      // ignore
    }

    return url;
  }
}
