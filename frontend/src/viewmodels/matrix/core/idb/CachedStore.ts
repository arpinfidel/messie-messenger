import QuickLRU from 'quick-lru';
import { DbConnection } from './DbConnection';

export class CachedStore<K, V> {
  private cache: QuickLRU<K, V>;

  constructor(
    private readonly conn: DbConnection,
    private readonly store: string,
    private readonly keyFn: (v: V) => K,
    cacheSize: number = 100
  ) {
    this.cache = new QuickLRU<K, V>({ maxSize: cacheSize });
  }

  async put(value: V): Promise<void> {
    await this.conn.init();
    await this.conn.tx<void>(this.store, 'readwrite', (s) => {
      s.put(value as any);
    });
    this.cache.set(this.keyFn(value), value);
  }

  async putMany(values: V[]): Promise<void> {
    if (!values.length) return;
    await this.conn.init();
    await this.conn.tx<void>(this.store, 'readwrite', (s) => {
      for (const v of values) {
        s.put(v as any);
      }
    });
    for (const v of values) this.cache.set(this.keyFn(v), v);
  }

  async get(key: K): Promise<V | undefined> {
    if (this.cache.has(key)) return this.cache.get(key);
    await this.conn.init();
    return this.conn.tx<V | undefined>(this.store, 'readonly', (s) => {
      const req = s.get(key as any);
      return new Promise<V | undefined>((resolve, reject) => {
        req.onsuccess = () => {
          const result = req.result as V | undefined;
          if (result !== undefined) this.cache.set(key, result);
          resolve(result);
        };
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async getAll(): Promise<V[]> {
    await this.conn.init();
    return this.conn.tx<V[]>(this.store, 'readonly', (s) => {
      const req = s.getAll();
      return new Promise<V[]>((resolve, reject) => {
        req.onsuccess = () => {
          const res = (req.result as V[]) || [];
          for (const v of res) this.cache.set(this.keyFn(v), v);
          resolve(res);
        };
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }
}
