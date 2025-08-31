import * as matrixSdk from 'matrix-js-sdk';
import type { RepoEvent, TimelineRepositoryOptions } from './TimelineRepository';
import { Direction } from 'matrix-js-sdk/lib/models/event-timeline';
import { MatrixDataStore } from './MatrixDataStore';
import { IndexedDbCache } from './IndexedDbCache';

/**
 * Data layer that talks to the SDK, converts events, and populates MatrixDataStore.
 */
export class MatrixDataLayer {
  private pageSize: number;
  private db = new IndexedDbCache();

  constructor(
    private readonly store: MatrixDataStore,
    private readonly opts: TimelineRepositoryOptions
  ) {
    this.pageSize = opts.pageSize ?? 20;
  }

  private get client(): matrixSdk.MatrixClient | null {
    return this.opts.getClient();
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

  /** Ingest rooms from the SDK into the store (id + name only). */
  ingestInitialRooms(): void {
    const c = this.client;
    if (!c) return;
    const rooms = c.getRooms() ?? [];
    for (const r of rooms) {
      this.store.upsertRoom(r.roomId, r.name || r.roomId);
      // persist minimal room record (latestTimestamp may be set later by events)
      this.db.putRoom({ id: r.roomId, name: r.name || r.roomId, latestTimestamp: this.store.getRooms().find(x=>x.id===r.roomId)?.latestTimestamp || 0 }).catch(() => {});
    }
    this.saveToCache();
  }

  /** Ensure initial page from live timeline is in the store for a room. */
  async fetchInitial(roomId: string, limit = this.pageSize) {
    const c = this.client;
    if (!c) throw new Error('Matrix client not available');
    const room = c.getRoom(roomId);
    if (!room) return { events: [] as RepoEvent[], toToken: null as string | null };

    const live = room.getLiveTimeline();
    const all = live.getEvents();
    const pick = all.slice(-limit);

    const converted: RepoEvent[] = [];
    const seenSenders = new Set<string>();
    for (const ev of pick) {
      const re = await this.toRepoEvent(ev);
      if (re) {
        converted.push(re);
        if (re.sender) seenSenders.add(re.sender);
      }
    }

    // write to store
    if (converted.length) {
      this.store.prependEvents(roomId, converted);
      try {
        await this.db.putEvents(roomId, converted);
        const r = this.store.getRooms().find((x) => x.id === roomId);
        if (r) await this.db.putRoom({ id: r.id, name: r.name, latestTimestamp: r.latestTimestamp ?? 0 });
        // Persist sender profiles for this page
        const users: { userId: string; displayName?: string; avatarUrl?: string }[] = [];
        for (const uid of seenSenders) {
          const m = room.getMember(uid);
          if (m) {
            const mxc = (m as any).getMxcAvatarUrl ? (m as any).getMxcAvatarUrl() : undefined;
            const display = (m as any).rawDisplayName || m.name;
            this.store.upsertUser(uid, display, mxc ?? null);
            users.push({ userId: uid, displayName: display, avatarUrl: mxc });
          } else {
            this.store.upsertUser(uid);
            users.push({ userId: uid });
          }
        }
        if (users.length) await this.db.putUsers(users);
      } catch {}
    }

    const bToken = live.getPaginationToken(Direction.Backward) ?? null;
    this.store.setBackwardToken(roomId, bToken);
    try {
      await this.db.setBackwardToken(roomId, bToken);
    } catch {}
    this.saveToCache();

    return { events: converted, toToken: bToken };
  }

  /** Load one backward page and prepend to store. */
  async loadOlder(roomId: string, limit = this.pageSize) {
    const c = this.client;
    if (!c) throw new Error('Matrix client not available');
    const room = c.getRoom(roomId);
    if (!room) return null;

    const live = room.getLiveTimeline();
    const prevToken =
      live.getPaginationToken(Direction.Forward) ?? this.store.getBackwardToken(roomId) ?? null;
    if (!prevToken) return null;

    const ok = await c.paginateEventTimeline(live, { backwards: true, limit });
    if (!ok) return null;

    const windowEvents = live.getEvents().slice(0, limit);
    const converted: RepoEvent[] = [];
    const seenSenders = new Set<string>();
    for (const ev of windowEvents) {
      const re = await this.toRepoEvent(ev);
      if (re) {
        converted.push(re);
        if (re.sender) seenSenders.add(re.sender);
      }
    }

    if (converted.length) {
      this.store.prependEvents(roomId, converted);
      try {
        await this.db.putEvents(roomId, converted);
        const r = this.store.getRooms().find((x) => x.id === roomId);
        if (r) await this.db.putRoom({ id: r.id, name: r.name, latestTimestamp: r.latestTimestamp ?? 0 });
        // Persist sender profiles for this page
        const users: { userId: string; displayName?: string; avatarUrl?: string }[] = [];
        for (const uid of seenSenders) {
          const m = room.getMember(uid);
          if (m) {
            const mxc = (m as any).getMxcAvatarUrl ? (m as any).getMxcAvatarUrl() : undefined;
            const display = (m as any).rawDisplayName || m.name;
            this.store.upsertUser(uid, display, mxc ?? null);
            users.push({ userId: uid, displayName: display, avatarUrl: mxc });
          } else {
            this.store.upsertUser(uid);
            users.push({ userId: uid });
          }
        }
        if (users.length) await this.db.putUsers(users);
      } catch {}
    }

    const nextToken = live.getPaginationToken(Direction.Backward) ?? null;
    this.store.setBackwardToken(roomId, nextToken);
    try {
      await this.db.setBackwardToken(roomId, nextToken);
    } catch {}
    this.saveToCache();

    return { events: converted, fromToken: prevToken, toToken: nextToken };
  }

  /** Ingest one live SDK event into the store. */
  async ingestLiveEvent(ev: matrixSdk.MatrixEvent, room: matrixSdk.Room) {
    // Update room name if needed
    this.store.upsertRoom(room.roomId, room.name || room.roomId);
    const re = await this.toRepoEvent(ev);
    if (!re) return;
    this.store.appendEvent(room.roomId, re);
    try {
      await this.db.putEvents(room.roomId, [re]);
      await this.db.putRoom({ id: room.roomId, name: room.name || room.roomId, latestTimestamp: this.store.getRooms().find(x=>x.id===room.roomId)?.latestTimestamp || 0 });
      // Persist sender profile
      if (re.sender) {
        const m = room.getMember(re.sender);
        if (m) {
          const mxc = (m as any).getMxcAvatarUrl ? (m as any).getMxcAvatarUrl() : undefined;
          const display = (m as any).rawDisplayName || m.name;
          this.store.upsertUser(re.sender, display, mxc ?? null);
          await this.db.putUser({ userId: re.sender, displayName: display, avatarUrl: mxc });
        } else {
          this.store.upsertUser(re.sender);
          await this.db.putUser({ userId: re.sender });
        }
      }
    } catch {}
    this.saveToCache();
  }

  clearRoom(roomId: string) {
    this.store.clearRoom(roomId);
    this.db.clearRoom(roomId).catch(() => {});
    this.saveToCache();
  }

  // -------- Persistence API --------
  loadFromCache(limitPerRoom = 50): boolean {
    // Hydrate in-memory store from IndexedDB. Return true if any rooms found.
    // Note: this runs sync with async operations inside; we optimistically return based on queued ops.
    // Callers can proceed; the timeline service will update once hydrated.
    (async () => {
      try {
        await this.db.init();
        const currentUserId = await this.db.getMeta<string>('currentUserId');
        const currentUserDisplayName = await this.db.getMeta<string>('currentUserDisplayName');
        if (currentUserId) this.store.setCurrentUser(currentUserId, currentUserDisplayName);

        const rooms = await this.db.getRooms();
        for (const r of rooms) {
          this.store.upsertRoom(r.id, r.name, r.latestTimestamp ?? 0);
        }

        // Load users
        try {
          const users = await this.db.getUsers();
          for (const u of users) this.store.upsertUser(u.userId, u.displayName, u.avatarUrl);
        } catch {}

        // Load a small tail of events per room for previews
        for (const r of rooms) {
          try {
            const desc = await this.db.getEventsByRoom(r.id, limitPerRoom);
            const asc = desc.slice().reverse();
            if (asc.length) this.store.prependEvents(r.id, asc);
            const token = await this.db.getBackwardToken(r.id);
            if (token !== undefined) this.store.setBackwardToken(r.id, token ?? null);
          } catch {}
        }
      } catch {}
    })();
    // We cannot know synchronously, but return true if we at least started hydration.
    // The caller will sort items when data arrives.
    return true;
  }

  saveToCache(): void {
    // Persist current user and rooms eagerly.
    const userId = this.store.getCurrentUserId();
    const displayName = this.store.getCurrentUserDisplayName();
    if (userId) this.db.setMeta('currentUserId', userId).catch(() => {});
    if (displayName) this.db.setMeta('currentUserDisplayName', displayName).catch(() => {});

    const rooms = this.store.getRooms();
    this.db
      .putRooms(
        rooms.map((r) => ({ id: r.id, name: r.name, latestTimestamp: r.latestTimestamp ?? 0 }))
      )
      .catch(() => {});

    // Persist users
    const users = this.store.getUsers();
    if (users.length) this.db.putUsers(users.map((u) => ({ userId: u.userId, displayName: u.displayName ?? undefined, avatarUrl: u.avatarUrl ?? undefined }))).catch(() => {});
  }

  /** Query cached events by room from IndexedDB, newest first. */
  async queryEventsByRoom(
    roomId: string,
    limit = 50,
    beforeTs?: number
  ): Promise<RepoEvent[]> {
    return this.db.getEventsByRoom(roomId, limit, beforeTs);
  }
}
