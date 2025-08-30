// Lightweight IndexedDB helper for app-level Matrix caching
// Stores rooms, events (indexed by roomId+ts), pagination tokens, and meta

import type { RepoEvent } from './TimelineRepository';

export interface DbRoom {
  id: string;
  name: string;
  latestTimestamp?: number; // latest message-like ts
}

type TokenRecord = { roomId: string; backward: string | null };

type MetaRecord = { key: string; value: any };

const DB_NAME = 'mx-app-store';
const DB_VERSION = 1;

const STORES = {
  ROOMS: 'rooms',
  EVENTS: 'events',
  TOKENS: 'tokens',
  META: 'meta',
} as const;

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
}
