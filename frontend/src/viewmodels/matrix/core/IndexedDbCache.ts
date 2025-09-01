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
  private readonly rooms = new RoomsStore(this.conn);
  private readonly events = new EventsStore(this.conn);
  private readonly tokens = new TokensStore(this.conn);
  private readonly meta = new MetaStore(this.conn);
  private readonly users = new UsersStore(this.conn);
  private readonly media = new MediaStore(this.conn);
  private readonly members = new MembersStore(this.conn);

  // Connection lifecycle
  init(): Promise<void> {
    return this.conn.init();
  }

  // Rooms
  putRooms(rooms: DbRoom[]): Promise<void> {
    return this.rooms.putRooms(rooms);
  }
  putRoom(room: DbRoom): Promise<void> {
    return this.rooms.putRoom(room);
  }
  getRooms(): Promise<DbRoom[]> {
    return this.rooms.getRooms();
  }

  // Events
  putEvents(roomId: string, events: RepoEvent[]): Promise<void> {
    return this.events.putEvents(roomId, events);
  }
  getEventsByRoom(roomId: string, limit = 50, beforeTs?: number): Promise<RepoEvent[]> {
    return this.events.getEventsByRoom(roomId, limit, beforeTs);
  }

  // Tokens
  setBackwardToken(roomId: string, backward: string | null): Promise<void> {
    return this.tokens.setBackwardToken(roomId, backward);
  }
  getBackwardToken(roomId: string): Promise<string | null | undefined> {
    return this.tokens.getBackwardToken(roomId);
  }

  // Clear room (events + token)
  async clearRoom(roomId: string): Promise<void> {
    await this.events.deleteEventsByRoom(roomId);
    await this.tokens.deleteToken(roomId);
  }

  // Meta
  setMeta(key: string, value: any): Promise<void> {
    return this.meta.setMeta(key, value);
  }
  getMeta<T = any>(key: string): Promise<T | undefined> {
    return this.meta.getMeta<T>(key);
  }

  // Users
  putUsers(users: DbUser[]): Promise<void> {
    return this.users.putUsers(users);
  }
  putUser(user: DbUser): Promise<void> {
    return this.users.putUser(user);
  }
  getUsers(): Promise<DbUser[]> {
    return this.users.getUsers();
  }
  getUser(userId: string): Promise<DbUser | undefined> {
    return this.users.getUser(userId);
  }

  // Members
  replaceRoomMembers(
    roomId: string,
    members: { userId: string; displayName?: string; avatarUrl?: string; membership?: string }[]
  ): Promise<void> {
    return this.members.replaceRoomMembers(roomId, members);
  }
  getRoomMembers(roomId: string): Promise<DbMember[]> {
    return this.members.getRoomMembers(roomId);
  }

  // Media
  putMedia(rec: { key: string; ts: number; bytes: number; mime: string; blob: Blob }): Promise<void> {
    return this.media.putMedia(rec);
  }
  getMedia(
    key: string
  ): Promise<{ key: string; ts: number; bytes: number; mime: string; blob: Blob } | undefined> {
    return this.media.getMedia(key);
  }
  pruneMedia(maxEntries: number): Promise<void> {
    return this.media.pruneMedia(maxEntries);
  }
}
