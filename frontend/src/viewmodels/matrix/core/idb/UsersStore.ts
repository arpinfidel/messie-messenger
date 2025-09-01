import { DbConnection } from './DbConnection';
import { STORES, type DbUser } from './constants';

export class UsersStore {
  constructor(private readonly conn: DbConnection) {}

  async putUsers(users: DbUser[]): Promise<void> {
    if (!users.length) return;
    await this.conn.init();
    await this.conn.tx<void>(STORES.USERS, 'readwrite', (s) => {
      for (const u of users) s.put(u);
    });
  }

  putUser(user: DbUser): Promise<void> {
    return this.putUsers([user]);
  }

  async getUsers(): Promise<DbUser[]> {
    await this.conn.init();
    return this.conn.tx<DbUser[]>(STORES.USERS, 'readonly', (s) => {
      const req = s.getAll();
      return new Promise<DbUser[]>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any) || []);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async getUser(userId: string): Promise<DbUser | undefined> {
    await this.conn.init();
    return this.conn.tx<DbUser | undefined>(STORES.USERS, 'readonly', (s) => {
      const req = s.get(userId);
      return new Promise<DbUser | undefined>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any) || undefined);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }
}

