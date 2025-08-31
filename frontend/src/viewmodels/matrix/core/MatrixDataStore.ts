import type { RepoEvent } from './TimelineRepository';

export interface StoredRoom {
  id: string;
  name: string;
  latestTimestamp?: number; // latest message-like event ts
  avatarUrl?: string | null;
}

export interface StoredUser {
  userId: string;
  displayName?: string | null;
  avatarUrl?: string | null;
}

type Tokens = { backward?: string | null };

/**
 * Central in-memory store for Matrix data.
 * Holds rooms, events per room, and pagination tokens.
 */
export class MatrixDataStore {
  private rooms = new Map<string, StoredRoom>();
  private eventsByRoom = new Map<string, RepoEvent[]>();
  private tokensByRoom = new Map<string, Tokens>();

  private currentUserId: string | null = null;
  private currentUserDisplayName: string | null = null;
  private users = new Map<string, StoredUser>();

  setCurrentUser(userId: string, displayName?: string | null) {
    this.currentUserId = userId;
    if (displayName) this.currentUserDisplayName = displayName;
  }

  getCurrentUserId(): string | null {
    return this.currentUserId;
  }

  getCurrentUserDisplayName(): string | null {
    return this.currentUserDisplayName || this.currentUserId;
  }

  // --- Users ---
  upsertUser(userId: string, displayName?: string | null, avatarUrl?: string | null) {
    const prev = this.users.get(userId) || { userId };
    this.users.set(userId, {
      userId,
      displayName: displayName ?? prev.displayName ?? null,
      avatarUrl: avatarUrl ?? prev.avatarUrl ?? null,
    });
  }

  getUser(userId: string): StoredUser | undefined {
    return this.users.get(userId);
  }

  getUserDisplayName(userId: string): string | undefined {
    const u = this.users.get(userId);
    return (u?.displayName || undefined) ?? undefined;
  }

  getUsers(): StoredUser[] {
    return Array.from(this.users.values());
  }

  upsertRoom(id: string, name: string, latestTimestamp?: number, avatarUrl?: string | null) {
    const prev = this.rooms.get(id) || { id, name, latestTimestamp: 0, avatarUrl: null };
    const next: StoredRoom = {
      id,
      name: name ?? prev.name,
      latestTimestamp:
        typeof latestTimestamp === 'number' ? latestTimestamp : (prev.latestTimestamp ?? 0),
      avatarUrl: avatarUrl !== undefined ? avatarUrl : (prev as any).avatarUrl ?? null,
    };
    this.rooms.set(id, next);
  }

  getRooms(): StoredRoom[] {
    return Array.from(this.rooms.values());
  }

  clearRoom(roomId: string) {
    this.eventsByRoom.delete(roomId);
    this.tokensByRoom.delete(roomId);
  }

  private ensureRoomArrays(roomId: string) {
    if (!this.eventsByRoom.has(roomId)) this.eventsByRoom.set(roomId, []);
    if (!this.tokensByRoom.has(roomId)) this.tokensByRoom.set(roomId, {});
  }

  prependEvents(roomId: string, events: RepoEvent[]) {
    if (!events.length) return;
    this.ensureRoomArrays(roomId);
    const arr = this.eventsByRoom.get(roomId)!;
    this.eventsByRoom.set(roomId, [...events, ...arr]);
    // update latest timestamp
    const ts = this.findLatestMessageTs(events);
    if (typeof ts === 'number') this.bumpRoomLatest(roomId, ts);
  }

  appendEvent(roomId: string, event: RepoEvent) {
    this.ensureRoomArrays(roomId);
    this.eventsByRoom.get(roomId)!.push(event);
    const ts = this.findLatestMessageTs([event]);
    if (typeof ts === 'number') this.bumpRoomLatest(roomId, ts);
  }

  getEvents(roomId: string): RepoEvent[] {
    return this.eventsByRoom.get(roomId) ?? [];
  }

  getLatestEvent(roomId: string): RepoEvent | undefined {
    const arr = this.eventsByRoom.get(roomId);
    if (!arr || arr.length === 0) return undefined;
    return arr[arr.length - 1];
  }

  setBackwardToken(roomId: string, token: string | null) {
    this.ensureRoomArrays(roomId);
    this.tokensByRoom.get(roomId)!.backward = token ?? null;
  }

  getBackwardToken(roomId: string): string | null | undefined {
    return this.tokensByRoom.get(roomId)?.backward;
  }

  // -------- Persistence helpers --------
  toJSON(limitPerRoom = 50): any {
    const rooms = this.getRooms();
    const events: Record<string, any[]> = {};
    const tokens: Record<string, Tokens> = {};
    const users = this.getUsers();
    for (const r of rooms) {
      const arr = this.eventsByRoom.get(r.id) ?? [];
      events[r.id] = arr.slice(Math.max(0, arr.length - limitPerRoom));
      const t = this.tokensByRoom.get(r.id) ?? {};
      tokens[r.id] = { backward: t.backward ?? null };
    }
    return {
      currentUserId: this.currentUserId,
      currentUserDisplayName: this.currentUserDisplayName,
      rooms,
      users,
      events,
      tokens,
    };
  }

  fromJSON(snapshot: any) {
    try {
      this.rooms = new Map();
      this.eventsByRoom = new Map();
      this.tokensByRoom = new Map();

      if (snapshot.currentUserId) this.currentUserId = snapshot.currentUserId;
      if (snapshot.currentUserDisplayName)
        this.currentUserDisplayName = snapshot.currentUserDisplayName;

      const rooms: StoredRoom[] = snapshot.rooms || [];
      for (const r of rooms)
        this.rooms.set(r.id, {
          id: r.id,
          name: r.name,
          latestTimestamp: r.latestTimestamp ?? 0,
          avatarUrl: r.avatarUrl ?? null,
        });

      const users: StoredUser[] = snapshot.users || [];
      for (const u of users)
        this.users.set(u.userId, {
          userId: u.userId,
          displayName: u.displayName ?? null,
          avatarUrl: u.avatarUrl ?? null,
        });

      const events: Record<string, any[]> = snapshot.events || {};
      for (const roomId of Object.keys(events)) {
        this.eventsByRoom.set(roomId, events[roomId] as any[] as any);
      }

      const tokens: Record<string, Tokens> = snapshot.tokens || {};
      for (const roomId of Object.keys(tokens)) {
        this.tokensByRoom.set(roomId, { backward: tokens[roomId]?.backward ?? null });
      }
    } catch {
      // ignore corrupt cache
    }
  }

  // -------- internal helpers --------
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

  private bumpRoomLatest(roomId: string, ts: number) {
    const r = this.rooms.get(roomId);
    if (!r) return;
    if (!r.latestTimestamp || ts > r.latestTimestamp) {
      r.latestTimestamp = ts;
      this.rooms.set(roomId, r);
    }
  }
}
