import { DbConnection } from './DbConnection';
import { STORES, type DbTimelineEvent } from './constants';

const MIN_KEY = Number.MIN_SAFE_INTEGER;
const MAX_KEY = Number.MAX_SAFE_INTEGER;

export class TimelineStore {
  constructor(private readonly conn: DbConnection, private readonly maxPerRoom = 120) {}

  async putEvents(events: DbTimelineEvent[]): Promise<void> {
    if (!events.length) return;
    await this.conn.init();
    const byRoom = new Map<string, DbTimelineEvent[]>();
    for (const ev of events) {
      if (!ev?.roomId) continue;
      const list = byRoom.get(ev.roomId) ?? [];
      list.push(ev);
      byRoom.set(ev.roomId, list);
    }

    for (const [roomId, roomEvents] of byRoom) {
      roomEvents.sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
      await this.conn.tx<void>(STORES.TIMELINE_EVENTS, 'readwrite', (store) => {
        for (const ev of roomEvents) {
          store.put(ev);
        }

        if (this.maxPerRoom <= 0) {
          return;
        }

        const idx = store.index('byRoomAndIndex');
        const range = IDBKeyRange.bound([roomId, MIN_KEY], [roomId, MAX_KEY]);
        const cursorReq = idx.openCursor(range, 'prev');
        let kept = 0;
        cursorReq.onsuccess = () => {
          const cursor = cursorReq.result as IDBCursorWithValue | null;
          if (!cursor) return;
          kept += 1;
          if (kept > this.maxPerRoom) {
            cursor.delete();
          }
          cursor.continue();
        };
      });
    }
  }

  async getEvents(
    roomId: string,
    beforeIndex: number | null,
    limit: number
  ): Promise<DbTimelineEvent[]> {
    if (!roomId || limit <= 0) return [];
    await this.conn.init();
    return this.conn.tx<DbTimelineEvent[]>(STORES.TIMELINE_EVENTS, 'readonly', (store) => {
      const idx = store.index('byRoomAndIndex');
      const upper = beforeIndex == null ? MAX_KEY : beforeIndex;
      const range = beforeIndex == null
        ? IDBKeyRange.bound([roomId, MIN_KEY], [roomId, MAX_KEY])
        : IDBKeyRange.bound([roomId, MIN_KEY], [roomId, upper], false, true);
      const req = idx.openCursor(range, 'prev');
      const acc: DbTimelineEvent[] = [];
      req.onsuccess = () => {
        const cursor = req.result as IDBCursorWithValue | null;
        if (!cursor) {
          return;
        }
        acc.push(cursor.value as DbTimelineEvent);
        if (acc.length < limit) {
          cursor.continue();
        }
      };
      return acc as unknown as DbTimelineEvent[];
    }).then((events) => {
      const ordered = events.slice().reverse();
      return ordered;
    });
  }

  async clearRoom(roomId: string): Promise<void> {
    if (!roomId) return;
    await this.conn.init();
    await this.conn.tx<void>(STORES.TIMELINE_EVENTS, 'readwrite', (store) => {
      const idx = store.index('byRoomId');
      const range = IDBKeyRange.only(roomId);
      const req = idx.openCursor(range);
      req.onsuccess = () => {
        const cursor = req.result as IDBCursorWithValue | null;
        if (!cursor) return;
        cursor.delete();
        cursor.continue();
      };
    });
  }
}
