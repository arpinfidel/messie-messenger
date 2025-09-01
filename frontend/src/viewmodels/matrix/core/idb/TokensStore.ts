import { DbConnection } from './DbConnection';
import { STORES, type TokenRecord } from './constants';

export class TokensStore {
  constructor(private readonly conn: DbConnection) {}

  async setBackwardToken(roomId: string, backward: string | null): Promise<void> {
    await this.conn.init();
    await this.conn.tx<void>(STORES.TOKENS, 'readwrite', (s) => {
      const rec: TokenRecord = { roomId, backward: backward ?? null };
      s.put(rec);
    });
  }

  async getBackwardToken(roomId: string): Promise<string | null | undefined> {
    await this.conn.init();
    return this.conn.tx<string | null | undefined>(STORES.TOKENS, 'readonly', (s) => {
      const req = s.get(roomId);
      return new Promise<string | null | undefined>((resolve, reject) => {
        req.onsuccess = () => resolve((req.result as any)?.backward ?? null);
        req.onerror = () => reject(req.error);
      }) as any;
    });
  }

  async deleteToken(roomId: string): Promise<void> {
    await this.conn.init();
    await this.conn.tx<void>(STORES.TOKENS, 'readwrite', (s) => {
      s.delete(roomId);
    });
  }
}

