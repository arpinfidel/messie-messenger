// Split IndexedDbCache into a small façade delegating to per-store classes.
import type { RepoEvent } from './TimelineRepository';
import { DbConnection } from './idb/DbConnection';
import { RoomsStore } from './idb/RoomsStore';
import { EventsStore } from './idb/EventsStore';
import { TokensStore } from './idb/TokensStore';
import { MetaStore } from './idb/MetaStore';
import { UsersStore } from './idb/UsersStore';
import { MediaStore } from './idb/MediaStore';
import { MembersStore } from './idb/MembersStore';
import type { DbRoom, DbUser, DbMember } from './idb/constants';

export class IndexedDbCache {
  private readonly conn = new DbConnection();
  private readonly events = new EventsStore(this.conn);
  private readonly tokens = new TokensStore(this.conn);
  private readonly meta = new MetaStore(this.conn);
  private readonly media = new MediaStore(this.conn);
  private readonly members = new MembersStore(this.conn);

  // Cache for per-room monotonic event indexes
  private readonly indexCache = new Map<string, number>();

  readonly rooms = new RoomsStore(this.conn);
  readonly users = new UsersStore(this.conn);

  // Connection lifecycle
  init(): Promise<void> {
    return this.conn.init();
  }

  // Events
  putEvents(roomId: string, events: RepoEvent[]): Promise<void> {
    return this.events.putEvents(roomId, events);
  }
  getLatestEventsByRoom(roomId: string, limit = 50, beforeIndex?: number): Promise<RepoEvent[]> {
    return this.events.getLatestEventsByRoom(roomId, limit, beforeIndex);
  }
  getEventsByRoom(roomId: string, limit = 50, beforeIndex?: number): Promise<RepoEvent[]> {
    return this.events.getEventsByRoom(roomId, limit, beforeIndex);
  }
  getEventById(eventId: string): Promise<RepoEvent | undefined> {
    return this.events.getEventById(eventId);
  }

  /**
   * Generate the next monotonic index for a room. Persist the latest index in
   * the meta store so it survives reloads.
   */
  async nextEventIndex(roomId: string): Promise<number> {
    let current = this.indexCache.get(roomId);
    if (current == null) {
      current = (await this.meta.getMeta<number>(`idx:${roomId}`)) ?? 0;
      if (!current) {
        const last = await this.events.getEventsByRoom(roomId, 1);
        current = last[0]?.index ?? 0;
      }
    }
    const next = current + 1;
    this.indexCache.set(roomId, next);
    await this.meta.setMeta(`idx:${roomId}`, next);
    return next;
  }

  // Tokens
  setBackwardToken(roomId: string, backward: string | null): Promise<void> {
    return this.tokens.setBackwardToken(roomId, backward);
  }
  getBackwardToken(roomId: string): Promise<string | null | undefined> {
    return this.tokens.getBackwardToken(roomId);
  }

  // Meta
  setMeta(key: string, value: any): Promise<void> {
    return this.meta.setMeta(key, value);
  }
  getMeta<T = any>(key: string): Promise<T | undefined> {
    return this.meta.getMeta<T>(key);
  }

  // Members
  setRoomMembers(
    roomId: string,
    members: {
      userId: string;
      displayName?: string;
      avatarUrl?: string;
      avatarMxcUrl?: string;
      membership?: string;
      lastReadTs: number;
    }[]
  ): Promise<void> {
    const normalized = members.map((m) => ({
      userId: m.userId,
      displayName: m.displayName,
      avatarUrl: m.avatarUrl ?? m.avatarMxcUrl,
      membership: m.membership,
      lastReadTs: m.lastReadTs,
    }));
    return this.members.setRoomMembers(roomId, normalized as any);
  }
  getRoomMembers(roomId: string): Promise<DbMember[]> {
    return this.members.getRoomMembers(roomId);
  }

  // Media
  putMedia(rec: {
    status: number;
    key: string;
    ts: number;
    bytes: number;
    mime: string;
    blob: Blob;
  }): Promise<void> {
    return this.media.putMedia(rec);
  }
  getMedia(
    key: string
  ): Promise<
    { status: number; key: string; ts: number; bytes: number; mime: string; blob: Blob } | undefined
  > {
    return this.media.getMedia(key);
  }
  pruneMedia(maxEntries: number): Promise<void> {
    return this.media.pruneMedia(maxEntries);
  }
}
