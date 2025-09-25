import { DbConnection } from './DbConnection';
import { STORES, type DbMember } from './constants';

export class MembersStore {
  constructor(private readonly conn: DbConnection) {}

  async getRoomMembers(roomId: string): Promise<DbMember[]> {
    await this.conn.init();
    return this.conn.tx<DbMember[]>(STORES.MEMBERS, 'readonly', (store) => {
      const index = store.index('byRoomId');
      const range = IDBKeyRange.only(roomId);
      const req = index.getAll(range) as IDBRequest<DbMember[]>;
      return new Promise<DbMember[]>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as DbMember[]) || []);
        req.onerror = () => reject(req.error);
      }) as unknown as DbMember[];
    });
  }

  async replaceRoomMembers(roomId: string, members: DbMember[]): Promise<void> {
    await this.conn.init();
    await this.conn.tx<void>(STORES.MEMBERS, 'readwrite', (store) => {
      const index = store.index('byRoomId');
      const range = IDBKeyRange.only(roomId);
      const existingKeysReq = index.getAllKeys(range) as IDBRequest<IDBValidKey[]>;
      const done = new Promise<void>((resolve, reject) => {
        existingKeysReq.onsuccess = () => {
          const keys = (existingKeysReq.result as IDBValidKey[]) || [];
          for (const key of keys) {
            store.delete(key);
          }
          for (const member of members) {
            store.put(member);
          }
          resolve();
        };
        existingKeysReq.onerror = () => reject(existingKeysReq.error);
      });
      return done as unknown as void;
    });
  }
}
