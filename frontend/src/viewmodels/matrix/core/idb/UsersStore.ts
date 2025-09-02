import { DbConnection } from './DbConnection';
import { STORES, type DbUser } from './constants';
import { CachedStore } from './CachedStore';

export class UsersStore extends CachedStore<string, DbUser> {
  constructor(conn: DbConnection, cacheSize = 100) {
    super(conn, STORES.USERS, (u) => u.userId, cacheSize);
  }
}
