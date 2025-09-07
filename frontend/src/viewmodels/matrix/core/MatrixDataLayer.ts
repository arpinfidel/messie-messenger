import * as matrixSdk from 'matrix-js-sdk';
import { MatrixEvent, MatrixEventEvent, type IEvent } from 'matrix-js-sdk/lib/models/event';
import type { RepoEvent } from './TimelineRepository';
import { Direction } from 'matrix-js-sdk/lib/models/event-timeline';
import { IndexedDbCache } from './IndexedDbCache';
import { AvatarResolver } from './AvatarResolver';
import { MediaResolver } from './MediaResolver';
import type { DbMember, DbUser } from './idb/constants';
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
    this.bind();
    return this;
  }

  onRepoEvent(listener: (ev: RepoEvent, room: matrixSdk.Room) => void): () => void {
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
      const members = await this.db.getRoomMembers(roomId);
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
    this.handleEvents(c);
    this.handleUnreadNotifications(c);
    this.handleReceipts(c);
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
    const m = room.getMembers() || [];
    if (!m || m.length === 0) {
      console.warn(`[MatrixDataLayer] getRoomMembers(${roomId}) → no members`);
      // Do not overwrite cached members with empty set; return what we have
      return members;
    }
    const oldMembersById = members.reduce(
      (acc, m) => {
        acc[m.userId] = m;
        return acc;
      },
      {} as Record<string, DbMember>
    );
    const newMembers = Array.from(m).map((m) => ({
      ...m,
      lastReadTs: oldMembersById[m.userId]?.lastReadTs || 0,
    }));
    console.log('[MatrixDataLayer] getRoomMembers', roomId, newMembers);

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
      await this.opts.tryDecryptEvent(ev);
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
        await this.opts.waitForPrepared();
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
        const syncState = (client as any)?.getSyncState?.();
        const isTrueLive = data?.liveEvent === true && syncState === 'SYNCING';
        if (isTrueLive) {
          // Do not touch unread here; rely on SDK UnreadNotifications
          const existing = await this.db.rooms.get(room.roomId);
          await this.db.rooms.put({
            id: room.roomId,
            name: room.name || room.roomId,
            latestTimestamp: ev.getTs(),
            avatarMxcUrl: room.getMxcAvatarUrl() || undefined,
            unreadCount: existing?.unreadCount ?? 0,
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
            this.unreadEventEmitter.emit(room.roomId, total ?? 0);
          } catch (err) {
            console.warn('[MatrixDataLayer] Failed to update unread from SDK', err);
          }
        };

        // Listen for future changes
        room.on(matrixSdk.RoomEvent.UnreadNotifications, writeUnread);
        // Seed initial value so first login reflects server state
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

      const updates: Record<string, number> = {};

      for (const [eventId, receiptTypes] of Object.entries<any>(content)) {
        const reads = receiptTypes?.['m.read'];
        if (!reads) continue;
        for (const [userId, meta] of Object.entries<any>(reads)) {
          updates[userId] = meta.ts;
        }
      }

      // If there are no receipts in this payload, skip to avoid accidental wipes.
      if (Object.keys(updates).length === 0) {
        console.warn('[MatrixDataLayer] handleReceipts: empty receipt payload');
        return;
      }

      // Single batch write to IDB for all user updates in this payload
      const members = await this.db.getRoomMembers(room.roomId);
      const updated = members.map((m) => ({
        userId: m.userId,
        displayName: m.displayName,
        avatarUrl: m.avatarUrl,
        membership: m.membership,
        lastReadTs: Math.max(m.lastReadTs || 0, updates[m.userId] || 0),
      }));
      console.log('[MatrixDataLayer] handleReceipts', room.roomId, updated);
      // Do not write if we have no members yet to merge into; seeding will happen via syncRoom.
      if (!members.length || !updated.length) {
        console.warn('[MatrixDataLayer] handleReceipts: no members to update', members);
        // Proactively seed members to avoid staying empty
        try {
          void this.syncRoom(room.roomId);
        } catch {}
      } else {
        await this.db.setRoomMembers(room.roomId, updated);
      }

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
    const existing = await this.db.rooms.get(roomId);
    if (!existing) return;
    await this.db.rooms.put({
      id: roomId,
      name: existing.name || roomId,
      latestTimestamp: existing.latestTimestamp ?? 0,
      avatarMxcUrl: existing.avatarMxcUrl,
      unreadCount: count,
    });
    this.unreadEventEmitter.emit(roomId, count);
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
        const sdkEv = room.findEventById(re.eventId);
        if (sdkEv) {
          const onDecrypted = async () => {
            if (sdkEv.isDecryptionFailure()) return;
            const updated = await this.toRepoEvent(sdkEv);
            if (updated) this.repoEventEmitter.emit(updated, room);
            sdkEv.off(MatrixEventEvent.Decrypted, onDecrypted);
          };
          sdkEv.on(MatrixEventEvent.Decrypted, onDecrypted);
        }
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
      await this.syncRoom(r.id);
    }
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

      // Update room record
      const existing = await this.db.rooms.get(room.roomId);
      await this.db.rooms.put({
        id: room.roomId,
        name: room.name || room.roomId,
        latestTimestamp: room.getLastActiveTimestamp(),
        avatarMxcUrl: room.getMxcAvatarUrl() || existing?.avatarMxcUrl,
        unreadCount: existing?.unreadCount ?? 0,
      });

      // Persist current members
      const members = room.getMembers()?.filter((m) => m.membership === 'join') || [];
      if (members.length)
        await this.db.users.putMany(
          members.map((x) => ({
            userId: x.userId,
            displayName: x.rawDisplayName || x.name,
            avatarMxcUrl: x.getMxcAvatarUrl(),
          }))
        );

      // Persist last-read timestamps for other members (exclude self)
      const self = this.currentUserId;
      const readUpdates: Record<string, number> = {};
      for (const m of members) {
        if (!m?.userId || m.userId === self) continue;
        const upToId = room.getEventReadUpTo?.(m.userId) as string | undefined;
        if (!upToId) continue;
        const cached = await this.db.getEventById(upToId);
        let ts = cached?.originServerTs || 0;
        if (!ts) {
          const sdkEv = room.findEventById(upToId);
          ts = sdkEv?.getTs?.() ?? 0;
        }
        if (ts) readUpdates[m.userId] = Math.max(readUpdates[m.userId] || 0, ts);
      }
      if (Object.keys(readUpdates).length) {
        const curr = await this.db.getRoomMembers(room.roomId);
        const currById = curr.reduce(
          (acc, m) => ({
            ...acc,
            [m.userId]: m,
          }),
          {} as Record<string, DbMember>
        );

        const merged = members.map((m) => ({
          userId: m.userId,
          displayName: m.rawDisplayName || m.name,
          avatarUrl: m.getMxcAvatarUrl(),
          membership: m.membership,
          lastReadTs: Math.max(currById[m.userId]?.lastReadTs || 0, readUpdates[m.userId] || 0),
        }));
        console.log('[MatrixDataLayer] syncRoom', room.roomId, merged);
        await this.db.setRoomMembers(room.roomId, merged);
      }
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
      } catch (err) {
        console.warn('[MatrixDataLayer] Failed to cache avatar in IDB', err);
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
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to cache image in IDB', err);
    }

    return url;
  }
}
