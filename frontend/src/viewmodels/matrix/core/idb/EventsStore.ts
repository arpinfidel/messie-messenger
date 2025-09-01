import { DbConnection } from './DbConnection';
import { STORES } from './constants';
import type { RepoEvent } from '../TimelineRepository';

export class EventsStore {
  constructor(private readonly conn: DbConnection) {}

  async putEvents(_roomId: string, events: RepoEvent[]): Promise<void> {
    if (!events.length) return;
    await this.conn.init();
    await this.conn.tx<void>(STORES.EVENTS, 'readwrite', (s) => {
      for (const ev of events) s.put(ev);
    });
  }

  async getEventsByRoom(
    roomId: string,
    limit = 50,
    beforeTs?: number
  ): Promise<RepoEvent[]> {
    await this.conn.init();
    const MAX = 9007199254740991; // Number.MAX_SAFE_INTEGER
    const upper = beforeTs ?? MAX;
    return new Promise<RepoEvent[]>((resolve, reject) => {
      try {
        const db = this.conn.ensure();
        const tx = db.transaction(STORES.EVENTS, 'readonly');
        const s = tx.objectStore(STORES.EVENTS);
        const idx = s.index('byRoomTs');
        const range = IDBKeyRange.bound([roomId, 0], [roomId, upper]);
        const out: RepoEvent[] = [];
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
      } catch (e) {
        reject(e);
      }
    });
  }

  async deleteEventsByRoom(roomId: string): Promise<void> {
    await this.conn.init();
    await new Promise<void>((resolve, reject) => {
      try {
        const db = this.conn.ensure();
        const tx = db.transaction(STORES.EVENTS, 'readwrite');
        const store = tx.objectStore(STORES.EVENTS);
        const idx = store.index('byRoomTs');
        const range = IDBKeyRange.bound([roomId, 0], [roomId, 9007199254740991]);
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
      } catch (e) {
        reject(e);
      }
    });
  }
}
