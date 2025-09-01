import { DbConnection } from './DbConnection';
import { STORES, type DbRoom } from './constants';

export class RoomsStore {
  constructor(private readonly conn: DbConnection) {}

  async putRooms(rooms: DbRoom[]): Promise<void> {
    if (!rooms.length) return;
    await this.conn.init();
    await this.conn.tx<void>(STORES.ROOMS, 'readwrite', (s) => {
      for (const r of rooms) s.put(r);
    });
  }

  putRoom(room: DbRoom): Promise<void> {
    return this.putRooms([room]);
  }

  async getRooms(): Promise<DbRoom[]> {
    await this.conn.init();
    return this.conn.tx<DbRoom[]>(STORES.ROOMS, 'readonly', (s) => {
      const req = s.getAll();
      return new Promise<DbRoom[]>((resolve, reject) => {
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }
}

