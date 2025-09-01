import { DbConnection } from './DbConnection';
import { STORES, type DbMember } from './constants';

export class MembersStore {
  constructor(private readonly conn: DbConnection) {}

  async replaceRoomMembers(
    roomId: string,
    members: { userId: string; displayName?: string; avatarUrl?: string; membership?: string }[]
  ): Promise<void> {
    await this.conn.init();

    // Delete existing members by room
    await new Promise<void>((resolve, reject) => {
      try {
        const db = this.conn.ensure();
        const tx = db.transaction([STORES.MEMBERS], 'readwrite');
        const store = tx.objectStore(STORES.MEMBERS);
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
      } catch (e) {
        reject(e);
      }
    });

    // Insert new members
    await this.conn.tx<void>(STORES.MEMBERS, 'readwrite', (s) => {
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
    await this.conn.init();
    return new Promise<DbMember[]>((resolve, reject) => {
      try {
        const db = this.conn.ensure();
        const tx = db.transaction([STORES.MEMBERS], 'readonly');
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
      } catch (e) {
        reject(e);
      }
    });
  }
}
