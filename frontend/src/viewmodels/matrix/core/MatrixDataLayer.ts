import * as matrixSdk from 'matrix-js-sdk';
import type { IEvent } from 'matrix-js-sdk';
import { MatrixEvent, MatrixEventEvent } from 'matrix-js-sdk/lib/models/event';
import type { RepoEvent } from './TimelineRepository';
import { Direction } from 'matrix-js-sdk/lib/models/event-timeline';
import { IndexedDbCache } from './IndexedDbCache';
import { AvatarResolver, type ResolveResult } from './AvatarResolver';
import { MediaResolver } from './MediaResolver';
import type { DbMember, DbRoom, DbUser } from './idb/constants';
import type { ImageContent } from 'matrix-js-sdk/lib/types';

type RepoEventListener = (ev: RepoEvent, room: matrixSdk.Room | null, meta?: { isLive?: boolean }) => void;

type SlidingSyncTimeline =
  | {
      events?: IEvent[];
      limited?: boolean;
    }
  | IEvent[]
  | undefined;

interface SlidingSyncRoomData {
  name?: string;
  avatar?: string;
  room_type?: string;
  bump_stamp?: number;
  required_state?: IEvent[];
  timeline?: SlidingSyncTimeline;
  unread_notifications?: {
    notification_count?: number;
    highlight_count?: number;
  };
  notification_count?: number;
  highlight_count?: number;
  initial?: boolean;
  limited?: boolean;
}

class RepoEventEmitter {
  private listeners = new Set<RepoEventListener>();

  on(listener: RepoEventListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(ev: RepoEvent, room: matrixSdk.Room | null, meta?: { isLive?: boolean }) {
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

type MessagesResponse = {
  chunk?: IEvent[];
  start?: string;
  end?: string;
  state?: IEvent[];
};

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
  private latestEventIdByRoom = new Map<string, string>();

  private async cacheTimelineEvents(events: RepoEvent[]): Promise<void> {
    if (!events.length) return;
    const payload = events
      .filter((ev) => ev?.eventId && ev.roomId)
      .map((ev) => ({ ...ev }));
    if (!payload.length) return;
    try {
      await this.db.timelines.putEvents(payload);
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to cache timeline events', err);
    }
  }

  private async loadCachedTimelineEvents(
    roomId: string,
    beforeIndex: number | null,
    limit: number
  ): Promise<{ events: RepoEvent[]; firstIndex: number | null }> {
    try {
      const cached = await this.db.timelines.getEvents(roomId, beforeIndex, limit);
      const events = cached.map((ev) => ({ ...ev }));
      const firstIndex = events.length ? events[0].index ?? null : beforeIndex;
      return { events, firstIndex: firstIndex ?? null };
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to load cached timeline events', err);
      return { events: [], firstIndex: beforeIndex };
    }
  }

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
    listener: (ev: RepoEvent, room: matrixSdk.Room | null, meta?: { isLive?: boolean }) => void
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

  async applySlidingSyncRoom(
    roomId: string,
    data: SlidingSyncRoomData,
    opts: { isInitial?: boolean } = {}
  ): Promise<void> {
    const requiredState = data.required_state;
    const nameContent = this.extractRequiredStateValue<{ name?: string }>(
      requiredState,
      'm.room.name'
    );
    const avatarContent = this.extractRequiredStateValue<{ url?: string }>(
      requiredState,
      'm.room.avatar'
    );

    const bumpStamp = Number.isFinite(data.bump_stamp)
      ? (data.bump_stamp as number)
      : undefined;
    const unreadCount =
      data.highlight_count ??
      data.unread_notifications?.highlight_count ??
      data.notification_count ??
      data.unread_notifications?.notification_count ??
      undefined;

    this.upsertRoomSummaryFromSlidingSync(roomId, {
      name: data.name ?? nameContent?.name,
      avatarMxcUrl: (data.avatar as string | undefined) ?? avatarContent?.url,
      latestTimestamp: bumpStamp,
      unreadCount,
    });

    const timelineSource = data.timeline;
    let timelineEvents: IEvent[] = [];
    if (Array.isArray(timelineSource)) {
      timelineEvents = timelineSource as IEvent[];
    } else if (
      timelineSource &&
      typeof timelineSource === 'object' &&
      Array.isArray((timelineSource as { events?: IEvent[] }).events)
    ) {
      timelineEvents = ((timelineSource as { events?: IEvent[] }).events ?? []) as IEvent[];
    }
    if (!timelineEvents.length) {
      return;
    }

    const client = this.client;
    const room = client?.getRoom(roomId) ?? null;
    const isInitial = opts?.isInitial ?? !!data.initial;
    let lastIndexed = this.inMemoryRooms.get(roomId)?.lastEvent?.index ?? 0;
    const toPersist: RepoEvent[] = [];

    // Timeline events are usually ordered oldest->newest; emit sequentially.
    for (const raw of timelineEvents) {
      const mxEvent = new matrixSdk.MatrixEvent(raw as IEvent);
      try {
        if (this.opts.tryDecryptEvent) {
          await this.opts.tryDecryptEvent(mxEvent);
        } else if (client?.decryptEventIfNeeded) {
          await client.decryptEventIfNeeded(mxEvent);
        }
      } catch (err) {
        console.warn('[MatrixDataLayer] Sliding sync decrypt failed', err);
      }

      const repoEvent = await this.toRepoEvent(mxEvent);
      if (!repoEvent) {
        continue;
      }

      const eventId = repoEvent.eventId;
      if (eventId && this.latestEventIdByRoom.get(roomId) === eventId) {
        continue;
      }

      const eventTs = mxEvent.getTs() || Date.now();
      if (lastIndexed && eventTs <= lastIndexed && !opts.isInitial) {
        // Skip events older than what we already have indexed
        continue;
      }
      repoEvent.index = eventTs;
      this.upsertRoomSummaryFromSlidingSync(roomId, {
        lastEvent: repoEvent,
        latestTimestamp: Math.max(eventTs, bumpStamp ?? eventTs),
      });
      lastIndexed = eventTs;
      if (eventId) {
        this.latestEventIdByRoom.set(roomId, eventId);
      }

      toPersist.push(repoEvent);
      this.repoEventEmitter.emit(repoEvent, room, { isLive: !isInitial });
    }

    if (toPersist.length) {
      await this.cacheTimelineEvents(toPersist);
    }
  }

  private get client(): matrixSdk.MatrixClient | null {
    return this.opts.getClient();
  }

  private extractRequiredStateValue<T = any>(
    stateEvents: IEvent[] | undefined,
    type: string,
    stateKey = ''
  ): T | undefined {
    if (!Array.isArray(stateEvents)) return undefined;
    const match = stateEvents.find(
      (ev) => ev?.type === type && (stateKey === undefined || ev?.state_key === stateKey)
    );
    return (match?.content as T | undefined) ?? undefined;
  }

  private upsertRoomSummaryFromSlidingSync(
    roomId: string,
    overrides: Partial<DbRoom>
  ): DbRoom {
    const existing = this.inMemoryRooms.get(roomId);

    const hasLastEventOverride = Object.prototype.hasOwnProperty.call(overrides, 'lastEvent');

    const updated: DbRoom = {
      id: roomId,
      name: overrides.name ?? existing?.name ?? roomId,
      avatarMxcUrl: overrides.avatarMxcUrl ?? existing?.avatarMxcUrl,
      latestTimestamp:
        overrides.latestTimestamp !== undefined
          ? overrides.latestTimestamp
          : existing?.latestTimestamp,
      unreadCount:
        overrides.unreadCount !== undefined
          ? overrides.unreadCount
          : existing?.unreadCount ?? 0,
      lastEvent: hasLastEventOverride
        ? (overrides.lastEvent as RepoEvent | null | undefined) ?? null
        : existing?.lastEvent ?? null,
    };

    this.inMemoryRooms.set(roomId, updated);

    if (overrides.unreadCount !== undefined && overrides.unreadCount !== existing?.unreadCount) {
      this.unreadEventEmitter.emit(roomId, overrides.unreadCount ?? 0);
    }

    void this.db.rooms.put(updated).catch((err) => {
      console.warn('[MatrixDataLayer] Failed to persist sliding sync room summary', err);
    });

    return updated;
  }

  private getUnreadFromRoom(room: matrixSdk.Room): number {
    try {
      return (
        (room.getUnreadNotificationCount(
          (matrixSdk as any).NotificationCountType?.Total ?? undefined
        ) as number) ?? 0
      );
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
    const unreadCount =
      overrides.unreadCount ?? existing?.unreadCount ?? this.getUnreadFromRoom(room);
    const avatarMxcUrl =
      overrides.avatarMxcUrl ?? existing?.avatarMxcUrl ?? room.getMxcAvatarUrl() ?? undefined;
    const name = overrides.name ?? existing?.name ?? room.name ?? room.roomId;
    const hasLastEventOverride = Object.prototype.hasOwnProperty.call(overrides, 'lastEvent');
    const lastEvent = hasLastEventOverride
      ? (overrides.lastEvent ?? null)
      : (existing?.lastEvent ?? null);

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

    const members = this.mapRoomMembers(room, roomId);
    if (members.length) {
      void this.persistRoomMembers(roomId, members);
    }
    return members;
  }

  async getRoomMembersSnapshot(roomId: string): Promise<DbMember[]> {
    const client = this.client;
    if (client) {
      const room = client.getRoom(roomId);
      if (room) {
        const members = this.mapRoomMembers(room, roomId);
        if (members.length) {
          void this.persistRoomMembers(roomId, members);
          return members;
        }
      }
    }

    try {
      const cached = await this.db.members.getRoomMembers(roomId);
      if (cached.length) {
        return cached;
      }
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to read cached members', err);
    }

    return [];
  }

  private mapRoomMembers(room: matrixSdk.Room, roomId: string): DbMember[] {
    const members = room.getMembers() || [];
    return members.map((member) => {
      const readUpTo = room.getEventReadUpTo?.(member.userId) as string | undefined;
      const ts = readUpTo ? (room.findEventById(readUpTo)?.getTs?.() ?? 0) : 0;
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
  }

  private async persistRoomMembers(roomId: string, members: DbMember[]): Promise<void> {
    try {
      const normalized = members.map((member) => ({
        ...member,
        key: member.key || `${roomId}|${member.userId}`,
        roomId,
      }));
      await this.db.members.replaceRoomMembers(roomId, normalized);
    } catch (err) {
      console.warn('[MatrixDataLayer] Failed to persist room members', roomId, err);
    }
  }

  async getUser(userId: string) {
    const u = await this.db.users.get(userId);
    if (u) return u;
    // Try to fetch from SDK if not in DB
    const c = this.client;
    if (!c) return undefined;
    const m = c.getUser(userId);
    if (!m) return undefined;
    const display = m.rawDisplayName;
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
    const idx =
      index ??
      (ev as any).mxIndex ??
      ev.getTs() ??
      Date.now();
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
    if (limit > 0) {
      const cachedBatch = await this.loadCachedTimelineEvents(roomId, beforeIndex, limit);
      if (cachedBatch.events.length) {
        return cachedBatch;
      }
    }
    if (beforeIndex == null && limit > 0) {
      const cached = this.inMemoryRooms.get(roomId)?.lastEvent;
      if (cached) {
        return { events: [cached], firstIndex: cached.index ?? null };
      }
      const latest = await this.getLatestMessagesFromServer(roomId, limit);
      if (latest) {
        return latest;
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
    if (limit <= 0) {
      return { events: [], firstIndex: beforeIndex };
    }

    const cachedBatch = await this.loadCachedTimelineEvents(roomId, beforeIndex, limit);
    let events = cachedBatch.events;

    if (events.length >= limit) {
      return { events, firstIndex: cachedBatch.firstIndex };
    }

    const remaining = limit - events.length;
    const fetchBefore = events.length
      ? events[0].index ?? beforeIndex
      : beforeIndex;
    const sdkBatch = await this.getRoomEventsFromSdk(roomId, fetchBefore, remaining);

    const mergedMap = new Map<string, RepoEvent>();
    const addEvent = (ev: RepoEvent) => {
      if (!ev) return;
      const key = ev.eventId || `${ev.roomId}|${ev.index || 0}`;
      if (!mergedMap.has(key)) {
        mergedMap.set(key, ev);
      }
    };

    for (const ev of events) addEvent(ev);
    for (const ev of sdkBatch.events) addEvent(ev);

    const merged = Array.from(mergedMap.values()).sort(
      (a, b) => (a.index ?? 0) - (b.index ?? 0)
    );

    const limited = merged.slice(-limit);
    const firstIndex = limited.length
      ? limited[0].index ?? null
      : sdkBatch.firstIndex ?? cachedBatch.firstIndex ?? beforeIndex;

    return {
      events: limited,
      firstIndex,
    };
  }

  private async getLatestMessagesFromServer(
    roomId: string,
    limit: number
  ): Promise<{ events: RepoEvent[]; firstIndex: number | null } | null> {
    if (limit <= 0) {
      return { events: [], firstIndex: null };
    }

    await this.opts.waitForPrepared();
    const client = this.client;
    if (!client) {
      return null;
    }

    const collected: RepoEvent[] = [];
    const seenIds = new Set<string>();
    const fetchSize = Math.max(limit, this.pageSize);
    let fromToken: string | undefined;
    let attempts = 0;

    while (collected.length < limit && attempts < 3) {
      attempts += 1;
      const params: Record<string, string> = {
        dir: Direction.Backward,
        limit: fetchSize.toString(),
      };
      if (fromToken) {
        params.from = fromToken;
      }

      let response: MessagesResponse;
      try {
        response = await client.http.authedRequest<MessagesResponse>(
          matrixSdk.Method.Get,
          `/rooms/${encodeURIComponent(roomId)}/messages`,
          params
        );
      } catch (err) {
        console.warn(`[MatrixDataLayer] Failed to fetch /messages for room ${roomId}`, err);
        return null;
      }

      const chunk = Array.isArray(response?.chunk) ? response.chunk : [];
      if (!chunk.length) {
        break;
      }

      for (const raw of chunk) {
        const mxEvent = new matrixSdk.MatrixEvent(raw as IEvent);
        const repoEvent = await this.toRepoEvent(mxEvent);
        if (!repoEvent) continue;
        if (repoEvent.eventId && seenIds.has(repoEvent.eventId)) continue;
        if (repoEvent.eventId) {
          seenIds.add(repoEvent.eventId);
        }
        const ts = mxEvent.getTs() || Date.now();
        repoEvent.index = ts;
        collected.push(repoEvent);
        if (collected.length >= limit) break;
      }

      if (collected.length >= limit) {
        break;
      }

      const nextToken = response?.end ?? null;
      if (!nextToken || nextToken === fromToken) {
        break;
      }
      fromToken = nextToken;
    }

    if (!collected.length) {
      return { events: [], firstIndex: null };
    }

    collected.sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
    const selected = collected.slice(-limit);
    const firstIndex = selected.length ? selected[0].index ?? null : null;

    const room = client.getRoom(roomId);
    if (room && selected.length) {
      this.upsertInMemoryRoom(room, { lastEvent: selected[selected.length - 1] });
    }

    if (selected.length) {
      await this.cacheTimelineEvents(selected);
    }

    return { events: selected, firstIndex };
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
    if (repoEvents.length) {
      await this.cacheTimelineEvents(repoEvents);
    }
    repoEvents.sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
    const firstIndex = repoEvents.length ? (repoEvents[0].index ?? null) : beforeIndex;
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
        void this.cacheTimelineEvents([re]);

        // Emit repo event; include whether this was a true live event
        this.repoEventEmitter.emit(re, room, { isLive: isTrueLive });

        const onDecrypted = async () => {
          if (ev.isDecryptionFailure()) return;
          try {
            const updated = await this.toRepoEvent(ev, eventIndex);
            if (updated) {
              this.upsertInMemoryRoom(room, { lastEvent: updated }, true);
              this.repoEventEmitter.emit(updated, room, { isLive: false });
              void this.cacheTimelineEvents([updated]);
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
            const total =
              (room.getUnreadNotificationCount(
                (matrixSdk as any).NotificationCountType?.Total ?? undefined
              ) as number) ?? 0;
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
      const members = this.mapRoomMembers(room, roomId);
      if (members.length) {
        void this.persistRoomMembers(roomId, members);
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
        return {
          status: 200,
          url,
          bytes: cached.bytes,
          mime: cached.mime,
          blob: cached.blob,
          objectUrl,
        };
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

  private buildAvatarFragment(
    tag: string | undefined,
    mxc: string,
    source: 'cache' | 'fresh'
  ): string {
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
