import { DB_NAME, DB_VERSION, STORES } from './constants';

export class DbConnection {
  private db: IDBDatabase | null = null;

  async init(): Promise<void> {
    if (this.db) return;
    this.db = await new Promise<IDBDatabase>((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        // Drop legacy stores that were used for the old timeline cache
        const legacyStores = ['events', 'tokens', 'members'];
        for (const store of legacyStores) {
          if (db.objectStoreNames.contains(store)) {
            db.deleteObjectStore(store);
          }
        }

        if (!db.objectStoreNames.contains(STORES.ROOMS)) {
          db.createObjectStore(STORES.ROOMS, { keyPath: 'id' });
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
