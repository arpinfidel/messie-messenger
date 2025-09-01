import { DB_NAME, DB_VERSION, STORES } from './constants';

export class DbConnection {
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

  ensure(): IDBDatabase {
    if (!this.db) throw new Error('DB not initialized');
    return this.db;
  }

  async tx<T = unknown>(
    store: string,
    mode: IDBTransactionMode,
    fn: (s: IDBObjectStore) => void
  ): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const db = this.ensure();
      const tx = db.transaction(store, mode);
      const s = tx.objectStore(store);
      let result: any = undefined;
      tx.oncomplete = () => resolve(result as T);
      tx.onerror = () => reject(tx.error);
      try {
        const maybe = fn(s);
        if (maybe !== undefined) result = maybe;
      } catch (e) {
        reject(e);
      }
    });
  }
}

