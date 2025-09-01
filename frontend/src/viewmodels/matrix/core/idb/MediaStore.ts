import { DbConnection } from './DbConnection';
import { STORES } from './constants';

export class MediaStore {
  constructor(private readonly conn: DbConnection) {}

  async putMedia(rec: {
    status: number;
    key: string;
    ts: number;
    bytes: number;
    mime: string;
    blob: Blob;
  }): Promise<void> {
    await this.conn.init();
    await this.conn.tx<void>(STORES.MEDIA, 'readwrite', (s) => {
      s.put(rec as any);
    });
  }

  async getMedia(
    key: string
  ): Promise<
    { status: number; key: string; ts: number; bytes: number; mime: string; blob: Blob } | undefined
  > {
    await this.conn.init();
    return this.conn.tx(STORES.MEDIA, 'readonly', (s) => {
      const req = s.get(key);
      return new Promise((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any) || undefined);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async pruneMedia(maxEntries: number): Promise<void> {
    await this.conn.init();
    const total = await this.conn.tx<number>(STORES.MEDIA, 'readonly', (s) => {
      const req = (s as any).getAllKeys?.();
      if (req) {
        return new Promise<number>((resolve, reject) => {
          req.onsuccess = () => resolve(((req.result as any[]) || []).length);
          req.onerror = () => reject(req.error);
        }) as any;
      }
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
        (s.transaction as IDBTransaction).onerror = () =>
          reject((s.transaction as IDBTransaction).error);
      }) as any;
    });

    const over = Math.max(0, (total || 0) - maxEntries);
    if (over <= 0) return;
    await this.conn.tx<void>(STORES.MEDIA, 'readwrite', (s) => {
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
