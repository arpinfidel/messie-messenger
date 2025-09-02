import { CachedStore } from './CachedStore';
import { DbConnection } from './DbConnection';
import { STORES, type DbRoom } from './constants';

export class RoomsStore extends CachedStore<string, DbRoom> {
  constructor(conn: DbConnection, cacheSize = 100) {
    super(conn, STORES.ROOMS, (u) => u.id, cacheSize);
  }
}
