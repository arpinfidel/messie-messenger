import { DbConnection } from './DbConnection';
import { STORES, type MetaRecord } from './constants';

export class MetaStore {
  constructor(private readonly conn: DbConnection) {}

  async setMeta(key: string, value: any): Promise<void> {
    await this.conn.init();
    await this.conn.tx<void>(STORES.META, 'readwrite', (s) => {
      const rec: MetaRecord = { key, value };
      s.put(rec);
    });
  }

  async getMeta<T = any>(key: string): Promise<T | undefined> {
    await this.conn.init();
    return this.conn.tx<T | undefined>(STORES.META, 'readonly', (s) => {
      const req = s.get(key);
      return new Promise<T | undefined>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any)?.value as T);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }
}

