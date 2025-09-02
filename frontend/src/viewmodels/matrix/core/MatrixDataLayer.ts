import * as matrixSdk from 'matrix-js-sdk';
import type { RepoEvent } from './TimelineRepository';
import { Direction } from 'matrix-js-sdk/lib/models/event-timeline';
import { IndexedDbCache } from './IndexedDbCache';
import { AvatarResolver } from './AvatarResolver';
import { MediaResolver } from './MediaResolver';
import type { DbUser } from './idb/constants';
import type { ImageContent } from 'matrix-js-sdk/lib/types';
import { MatrixViewModel } from '../MatrixViewModel';

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

  constructor(private readonly opts: MatrixDataLayerOptions) {
    this.pageSize = opts.pageSize ?? 20;
    this.avatarResolver = new AvatarResolver(opts.getClient, {
      maxMemEntries: 200,
      maxDbEntries: 200,
    });
    this.mediaResolver = new MediaResolver(opts.getClient, { maxEntries: 200 });
  }

  private get client(): matrixSdk.MatrixClient | null {
    return this.opts.getClient();
  }

  // ------------------------------------------------------------------
  // Current user helpers
  // ------------------------------------------------------------------

  setCurrentUser(userId: string, displayName?: string | null) {
    this.currentUserId = userId;
    if (displayName !== undefined) this.currentUserDisplayName = displayName || null;
    this.db.setMeta('currentUserId', userId).catch(() => {});
    if (displayName) this.db.setMeta('currentUserDisplayName', displayName).catch(() => {});
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
    return this.db.getRooms();
  }

  async getRoomMembers(roomId: string) {
    return this.db.getRoomMembers(roomId);
  }

  async getUser(userId: string) {
    const u = this.db.getUser(userId);
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
      await this.db.putUser(user);
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

  /** Refresh and cache joined room members (room -> members -> user link). */
  async refreshRoomMembers(roomId: string): Promise<void> {
    const c = this.client;
    if (!c) return;
    const room = c.getRoom(roomId);
    if (!room) return;
    try {
      const members = room.getMembers()?.filter((m) => (m as any).membership === 'join') || [];
      const out: {
        userId: string;
        displayName?: string;
        avatarUrl?: string;
        membership?: string;
      }[] = [];
      for (const m of members) {
        const userId = m.userId;
        const display = (m as any).rawDisplayName || m.name;
        const mxc = (m as any).getMxcAvatarUrl ? (m as any).getMxcAvatarUrl() : undefined;
        out.push({
          userId,
          displayName: display,
          avatarUrl: mxc,
          membership: (m as any).membership,
        });
      }
      await this.db.replaceRoomMembers(roomId, out);
      if (out.length)
        await this.db.putUsers(
          out.map((x) => ({
            userId: x.userId,
            displayName: x.displayName,
            avatarMxcUrl: x.avatarUrl,
          }))
        );
    } catch {}
  }

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

  /**
   * Ingest rooms from the SDK into IndexedDB.
   * Preserve any existing latestTimestamp to avoid resetting activity to 0.
   */
  async ingestInitialRooms(): Promise<void> {
    const c = this.client;
    if (!c) return;
    const rooms = c.getRooms() ?? [];

    // Read existing room records once to preserve their latestTimestamp values.
    let existing: { [id: string]: number | undefined } = {};
    let existingIds = new Set<string>();
    try {
      const current = await this.db.getRooms();
      for (const r of current) {
        existing[r.id] = r.latestTimestamp;
        existingIds.add(r.id);
      }
    } catch {
      // ignore cache read issues; proceed with defaults
    }

    for (const r of rooms) {
      const roomMxc = (r as any).getMxcAvatarUrl ? (r as any).getMxcAvatarUrl() : null;
      // Only create records for rooms we don't have yet to avoid clobbering
      // latestTimestamp that may already be up-to-date from live events.
      if (!existingIds.has(r.roomId)) {
        const preservedTs = existing[r.roomId];
        this.db
          .putRoom({
            id: r.roomId,
            name: r.name || r.roomId,
            latestTimestamp: preservedTs ?? 0,
            avatarMxcUrl: roomMxc || undefined,
          })
          .catch(() => {});
      }
      this.refreshRoomMembers(r.roomId).catch(() => {});
    }
    this.saveToCache();
  }

  /** Persist a set of SDK events to IndexedDB and update room/user metadata. */
  private async persistTimelineEvents(
    roomId: string,
    room: matrixSdk.Room,
    sdkEvents: matrixSdk.MatrixEvent[]
  ) {
    const converted: RepoEvent[] = [];
    const seenSenders = new Set<string>();
    for (const ev of sdkEvents) {
      const re = await this.toRepoEvent(ev);
      if (re) {
        converted.push(re);
        if (re.sender) seenSenders.add(re.sender);
      }
    }
    if (!converted.length) return;
    try {
      await this.db.putEvents(roomId, converted);
      const latest = this.findLatestMessageTs(converted);
      const existingRooms = await this.db.getRooms();
      const prev = existingRooms.find((r) => r.id === roomId)?.latestTimestamp || 0;
      const roomRec = {
        id: roomId,
        name: room.name || roomId,
        latestTimestamp: latest && latest > prev ? latest : prev,
        avatarMxcUrl: room.getMxcAvatarUrl() || undefined,
      };
      await this.db.putRoom(roomRec);
      const users: DbUser[] = [];
      for (const uid of seenSenders) {
        const m = room.getMember(uid);
        if (m) {
          const mxc = (m as any).getMxcAvatarUrl ? (m as any).getMxcAvatarUrl() : undefined;
          const display = (m as any).rawDisplayName || m.name;
          users.push({ userId: uid, displayName: display, avatarMxcUrl: mxc });
        } else {
          users.push({ userId: uid });
        }
      }
      if (users.length) await this.db.putUsers(users);
    } catch {}
    this.refreshRoomMembers(roomId).catch(() => {});
  }

  /**
   * Fetch a paginated set of events for a room. Uses cached events first and
   * falls back to the Matrix SDK when more events are needed. Always paginate
   * by TS. If events from DB are insufficient, fetch more from the SDK and
   * return last timestamp as the next token.
   */
  async getRoomMessages(
    roomId: string,
    beforeTs: number | null,
    limit = this.pageSize
  ): Promise<{ events: RepoEvent[]; firstTS: number | null }> {
    // Try to satisfy from cache first
    console.time(`[MatrixDataLayer] getRoomMessages(${roomId})`);
    let events = await this.db.getEventsByRoom(roomId, limit, beforeTs ?? undefined);
    console.timeEnd(`[MatrixDataLayer] getRoomMessages(${roomId})`);
    if (events.length >= limit) {
      console.log(
        `[MatrixDataLayer] getRoomMessages(${roomId}) → ${events.length} events from cache`
      );
      const firstTS = events.length ? events[events.length - 1].originServerTs : (beforeTs ?? null);
      events.reverse();
      return { events, firstTS: firstTS };
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
      const ok = await c.paginateEventTimeline(live, { backwards: true, limit: limit * 3 });
      if (ok) {
        const windowEvents = room.getLiveTimeline().getEvents();
        await this.persistTimelineEvents(roomId, room, windowEvents);
        remoteToken = room.getLiveTimeline().getPaginationToken(Direction.Backward);
      } else {
        remoteToken = null;
      }
    } else {
      console.log(
        `[MatrixDataLayer] getRoomMessages(${roomId}) → have token, paginate from ${token}`
      );
      live.setPaginationToken(token, Direction.Backward);
      const ok = await c.paginateEventTimeline(live, { backwards: true, limit: limit * 3 });
      if (ok) {
        const windowEvents = room.getLiveTimeline().getEvents();
        await this.persistTimelineEvents(roomId, room, windowEvents);
        remoteToken = room.getLiveTimeline().getPaginationToken(Direction.Backward);
      } else {
        remoteToken = token;
      }
    }
    await this.db.setBackwardToken(roomId, remoteToken);

    events = await this.db.getEventsByRoom(roomId, limit, beforeTs ?? undefined);
    const firstTS = events.length ? events[events.length - 1].originServerTs : (beforeTs ?? null);
    events.reverse();

    return { events, firstTS };
  }

  /** Ingest one live SDK event and persist it. */
  async ingestLiveEvent(ev: matrixSdk.MatrixEvent, room: matrixSdk.Room) {
    const re = await this.toRepoEvent(ev);
    if (!re) return;
    try {
      await this.db.putEvents(room.roomId, [re]);
      const existingRooms = await this.db.getRooms();
      const prev = existingRooms.find((r) => r.id === room.roomId)?.latestTimestamp || 0;
      const ts = this.findLatestMessageTs([re]) ?? prev;
      const roomMxc = (room as any).getMxcAvatarUrl ? (room as any).getMxcAvatarUrl() : undefined;
      await this.db.putRoom({
        id: room.roomId,
        name: room.name || room.roomId,
        latestTimestamp: ts,
        avatarMxcUrl: roomMxc,
      });
      if (re.sender) {
        const m = room.getMember(re.sender);
        if (m) {
          const mxc = (m as any).getMxcAvatarUrl ? (m as any).getMxcAvatarUrl() : undefined;
          const display = (m as any).rawDisplayName || m.name;
          await this.db.putUser({ userId: re.sender, displayName: display, avatarMxcUrl: mxc });
        } else {
          await this.db.putUser({ userId: re.sender });
        }
      }
      if (ev.getType() === 'm.room.member') {
        this.refreshRoomMembers(room.roomId).catch(() => {});
      }
    } catch {}
    this.saveToCache();
  }

  async clearRoom(roomId: string) {
    await this.db.clearRoom(roomId);
    this.saveToCache();
  }

  // ------------------------------------------------------------------
  // Persistence API
  // ------------------------------------------------------------------

  async loadFromCache(limitPerRoom = 5, onHydrated?: () => void): Promise<boolean> {
    try {
      await this.db.init();
      const [currentUserId, currentUserDisplayName] = await Promise.all([
        this.db.getMeta<string>('currentUserId'),
        this.db.getMeta<string>('currentUserDisplayName'),
      ]);
      if (currentUserId) this.currentUserId = currentUserId;
      if (currentUserDisplayName) this.currentUserDisplayName = currentUserDisplayName;
      onHydrated?.();
      return true;
    } catch (e) {
      console.error('[MatrixDataLayer] cache: hydration FAILED', e);
      return false;
    }
  }

  saveToCache(): void {
    if (this.currentUserId) this.db.setMeta('currentUserId', this.currentUserId).catch(() => {});
    if (this.currentUserDisplayName)
      this.db.setMeta('currentUserDisplayName', this.currentUserDisplayName).catch(() => {});
  }

  /** Query cached events by room from IndexedDB, newest first. */
  async queryEventsByRoom(roomId: string, limit = 50, beforeTs?: number): Promise<RepoEvent[]> {
    return this.db.getEventsByRoom(roomId, limit, beforeTs);
  }

  // ------------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------------

  private isMessageLike(ev: RepoEvent): boolean {
    const t = ev.type;
    return t === 'm.room.message' || t === 'm.room.encrypted';
  }

  private findLatestMessageTs(events: RepoEvent[]): number | undefined {
    let ts: number | undefined;
    for (const e of events) {
      if (!this.isMessageLike(e)) continue;
      const ets = e.originServerTs || 0;
      if (ets && (ts === undefined || ets > ts)) ts = ets;
    }
    return ts;
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
        return url;
      }
    }

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
