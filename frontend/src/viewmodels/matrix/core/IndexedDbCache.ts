// Lightweight IndexedDB helper for app-level Matrix caching
// Stores rooms, events (indexed by roomId+ts), pagination tokens, and meta

import type { RepoEvent } from './TimelineRepository';

export interface DbUser {
  userId: string;
  displayName?: string;
  avatarUrl?: string; // may be MXC URL
}

export interface DbRoom {
  id: string;
  name: string;
  latestTimestamp?: number; // latest message-like ts
  avatarUrl?: string; // room avatar MXC
}

type TokenRecord = { roomId: string; backward: string | null };

type MetaRecord = { key: string; value: any };

const DB_NAME = 'mx-app-store';
const DB_VERSION = 4;

const STORES = {
  ROOMS: 'rooms',
  EVENTS: 'events',
  TOKENS: 'tokens',
  META: 'meta',
  USERS: 'users',
  MEDIA: 'media', // blob cache (e.g., avatars)
  MEMBERS: 'members', // per-room members
} as const;

export interface DbMember {
  key: string; // `${roomId}|${userId}`
  roomId: string;
  userId: string;
  displayName?: string;
  avatarUrl?: string; // MXC URL
  membership?: string; // e.g., 'join', 'leave'
}

export class IndexedDbCache {
  private db: IDBDatabase | null = null;

  async init(): Promise<void> {
    if (this.db) return;
    this.db = await new Promise<IDBDatabase>((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(STORES.ROOMS)) {
          db.createObjectStore(STORES.ROOMS, { keyPath: 'id' });
        }
        if (!db.objectStoreNames.contains(STORES.EVENTS)) {
          const events = db.createObjectStore(STORES.EVENTS, { keyPath: 'eventId' });
          // Compound index: [roomId, originServerTs] for range queries by room
          events.createIndex('byRoomTs', ['roomId', 'originServerTs']);
        }
        if (!db.objectStoreNames.contains(STORES.TOKENS)) {
          db.createObjectStore(STORES.TOKENS, { keyPath: 'roomId' });
        }
        if (!db.objectStoreNames.contains(STORES.META)) {
          db.createObjectStore(STORES.META, { keyPath: 'key' });
        }
        if (!db.objectStoreNames.contains(STORES.USERS)) {
          db.createObjectStore(STORES.USERS, { keyPath: 'userId' });
        }
        if (!db.objectStoreNames.contains(STORES.MEDIA)) {
          const media = db.createObjectStore(STORES.MEDIA, { keyPath: 'key' });
          media.createIndex('byTs', 'ts');
        }
        if (!db.objectStoreNames.contains(STORES.MEMBERS)) {
          const members = db.createObjectStore(STORES.MEMBERS, { keyPath: 'key' });
          members.createIndex('byRoom', 'roomId');
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  private tx<T = unknown>(
    store: string,
    mode: IDBTransactionMode,
    fn: (s: IDBObjectStore) => void
  ): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      if (!this.db) return reject(new Error('DB not initialized'));
      const tx = this.db.transaction(store, mode);
      const s = tx.objectStore(store);
      let result: any = undefined;
      tx.oncomplete = () => resolve(result as T);
      tx.onerror = () => reject(tx.error);
      try {
        const maybe = fn(s);
        // allow fn to set result via closure
        if (maybe !== undefined) result = maybe;
      } catch (e) {
        reject(e);
      }
    });
  }

  async putRooms(rooms: DbRoom[]): Promise<void> {
    await this.init();
    await this.tx<void>(STORES.ROOMS, 'readwrite', (s) => {
      for (const r of rooms) s.put(r);
    });
  }

  async putRoom(room: DbRoom): Promise<void> {
    return this.putRooms([room]);
  }

  async getRooms(): Promise<DbRoom[]> {
    await this.init();
    return this.tx<DbRoom[]>(STORES.ROOMS, 'readonly', (s) => {
      const req = s.getAll();
      return new Promise<DbRoom[]>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any) || []);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async putEvents(roomId: string, events: RepoEvent[]): Promise<void> {
    if (!events.length) return;
    await this.init();
    await this.tx<void>(STORES.EVENTS, 'readwrite', (s) => {
      for (const ev of events) s.put(ev);
    });
  }

  async getEventsByRoom(roomId: string, limit = 50, beforeTs?: number): Promise<RepoEvent[]> {
    await this.init();
    const MAX = 9007199254740991; // Number.MAX_SAFE_INTEGER
    const upper = beforeTs ?? MAX;
    return new Promise<RepoEvent[]>((resolve, reject) => {
      if (!this.db) return reject(new Error('DB not initialized'));
      const tx = this.db.transaction(STORES.EVENTS, 'readonly');
      const s = tx.objectStore(STORES.EVENTS);
      const idx = s.index('byRoomTs');
      const range = IDBKeyRange.bound([roomId, 0], [roomId, upper]);
      const out: RepoEvent[] = [];
      // iterate newest first
      const cursorReq = idx.openCursor(range, 'prev');
      cursorReq.onsuccess = () => {
        const cursor = cursorReq.result as IDBCursorWithValue | null;
        if (!cursor || out.length >= limit) return;
        out.push(cursor.value as RepoEvent);
        cursor.continue();
      };
      cursorReq.onerror = () => reject(cursorReq.error);
      tx.oncomplete = () => resolve(out);
      tx.onerror = () => reject(tx.error);
    });
  }

  async setBackwardToken(roomId: string, backward: string | null): Promise<void> {
    await this.init();
    await this.tx<void>(STORES.TOKENS, 'readwrite', (s) => {
      const rec: TokenRecord = { roomId, backward: backward ?? null };
      s.put(rec);
    });
  }

  async getBackwardToken(roomId: string): Promise<string | null | undefined> {
    await this.init();
    return this.tx<string | null | undefined>(STORES.TOKENS, 'readonly', (s) => {
      const req = s.get(roomId);
      return new Promise<string | null | undefined>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any)?.backward ?? null);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async clearRoom(roomId: string): Promise<void> {
    await this.init();
    // delete events with this roomId via index scan
    await new Promise<void>((resolve, reject) => {
      if (!this.db) return reject(new Error('DB not initialized'));
      const tx = this.db.transaction([STORES.EVENTS, STORES.TOKENS], 'readwrite');
      const events = tx.objectStore(STORES.EVENTS);
      const idx = events.index('byRoomTs');
      const range = IDBKeyRange.bound([roomId, 0], [roomId, 9007199254740991]);
      const cursorReq = idx.openCursor(range);
      cursorReq.onsuccess = () => {
        const cursor = cursorReq.result as IDBCursorWithValue | null;
        if (!cursor) return;
        events.delete(cursor.primaryKey);
        cursor.continue();
      };
      cursorReq.onerror = () => reject(cursorReq.error);

      // delete token
      const tokens = tx.objectStore(STORES.TOKENS);
      tokens.delete(roomId);

      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  }

  async setMeta(key: string, value: any): Promise<void> {
    await this.init();
    await this.tx<void>(STORES.META, 'readwrite', (s) => {
      const rec: MetaRecord = { key, value };
      s.put(rec);
    });
  }

  async getMeta<T = any>(key: string): Promise<T | undefined> {
    await this.init();
    return this.tx<T | undefined>(STORES.META, 'readonly', (s) => {
      const req = s.get(key);
      return new Promise<T | undefined>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any)?.value as T);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  // --- Users table ---
  async putUsers(users: DbUser[]): Promise<void> {
    if (!users.length) return;
    await this.init();
    await this.tx<void>(STORES.USERS, 'readwrite', (s) => {
      for (const u of users) s.put(u);
    });
  }

  async putUser(user: DbUser): Promise<void> {
    return this.putUsers([user]);
  }

  async getUsers(): Promise<DbUser[]> {
    await this.init();
    return this.tx<DbUser[]>(STORES.USERS, 'readonly', (s) => {
      const req = s.getAll();
      return new Promise<DbUser[]>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any) || []);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async getUser(userId: string): Promise<DbUser | undefined> {
    await this.init();
    return this.tx<DbUser | undefined>(STORES.USERS, 'readonly', (s) => {
      const req = s.get(userId);
      return new Promise<DbUser | undefined>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any) || undefined);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  // --- Members table ---
  async replaceRoomMembers(
    roomId: string,
    members: { userId: string; displayName?: string; avatarUrl?: string; membership?: string }[]
  ): Promise<void> {
    await this.init();
    await new Promise<void>((resolve, reject) => {
      if (!this.db) return reject(new Error('DB not initialized'));
      const tx = this.db.transaction([STORES.MEMBERS], 'readwrite');
      const store = tx.objectStore(STORES.MEMBERS);
      // First, delete existing members by room
      const idx = store.index('byRoom');
      const range = IDBKeyRange.only(roomId);
      const cursorReq = idx.openCursor(range);
      cursorReq.onsuccess = () => {
        const cursor = cursorReq.result as IDBCursorWithValue | null;
        if (!cursor) return;
        store.delete(cursor.primaryKey);
        cursor.continue();
      };
      cursorReq.onerror = () => reject(cursorReq.error);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    // Insert new members
    await this.tx<void>(STORES.MEMBERS, 'readwrite', (s) => {
      for (const m of members) {
        const rec: DbMember = {
          key: `${roomId}|${m.userId}`,
          roomId,
          userId: m.userId,
          displayName: m.displayName,
          avatarUrl: m.avatarUrl,
          membership: m.membership,
        };
        s.put(rec as any);
      }
    });
  }

  async getRoomMembers(roomId: string): Promise<DbMember[]> {
    await this.init();
    return new Promise<DbMember[]>((resolve, reject) => {
      if (!this.db) return reject(new Error('DB not initialized'));
      const tx = this.db.transaction([STORES.MEMBERS], 'readonly');
      const store = tx.objectStore(STORES.MEMBERS);
      const idx = store.index('byRoom');
      const range = IDBKeyRange.only(roomId);
      const out: DbMember[] = [];
      const cursorReq = idx.openCursor(range);
      cursorReq.onsuccess = () => {
        const cursor = cursorReq.result as IDBCursorWithValue | null;
        if (!cursor) return;
        out.push(cursor.value as DbMember);
        cursor.continue();
      };
      cursorReq.onerror = () => reject(cursorReq.error);
      tx.oncomplete = () => resolve(out);
      tx.onerror = () => reject(tx.error);
    });
  }

  // ---- Media blob cache (avatars, thumbnails) ----
  async putMedia(rec: { key: string; ts: number; bytes: number; mime: string; blob: Blob }): Promise<void> {
    await this.init();
    await this.tx<void>(STORES.MEDIA, 'readwrite', (s) => {
      s.put(rec as any);
    });
  }

  async getMedia(key: string): Promise<{ key: string; ts: number; bytes: number; mime: string; blob: Blob } | undefined> {
    await this.init();
    return this.tx(STORES.MEDIA, 'readonly', (s) => {
      const req = s.get(key);
      return new Promise((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any) || undefined);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async pruneMedia(maxEntries: number): Promise<void> {
    await this.init();
    // Count entries first
    const total = await this.tx<number>(STORES.MEDIA, 'readonly', (s) => {
      const req = (s as any).getAllKeys?.();
      if (req) {
        return new Promise<number>((resolve, reject) => {
          req.onsuccess = () => resolve(((req.result as any[]) || []).length);
          req.onerror = () => reject(req.error);
        }) as any;
      }
      // Fallback: iterate
      return new Promise<number>((resolve, reject) => {
        let count = 0;
        const idx = s.index('byTs');
        const cursorReq = idx.openCursor();
        cursorReq.onsuccess = () => {
          const cursor = cursorReq.result as IDBCursorWithValue | null;
          if (!cursor) return;
          count++;
          cursor.continue();
        };
        cursorReq.onerror = () => reject(cursorReq.error);
        (s.transaction as IDBTransaction).oncomplete = () => resolve(count);
        (s.transaction as IDBTransaction).onerror = () => reject((s.transaction as IDBTransaction).error);
      }) as any;
    });

    const over = Math.max(0, (total || 0) - maxEntries);
    if (over <= 0) return;
    await this.tx<void>(STORES.MEDIA, 'readwrite', (s) => {
      let toDelete = over;
      const idx = s.index('byTs');
      const cursorReq = idx.openCursor(); // oldest first
      cursorReq.onsuccess = () => {
        const cursor = cursorReq.result as IDBCursorWithValue | null;
        if (!cursor || toDelete <= 0) return;
        const key = cursor.primaryKey;
        s.delete(key);
        toDelete--;
        cursor.continue();
      };
    });
  }
}
