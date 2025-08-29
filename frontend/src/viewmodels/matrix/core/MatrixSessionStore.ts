export interface MatrixSessionData {
  homeserverUrl: string;
  userId: string;
  accessToken: string;
  deviceId?: string;
}

const KEY = 'matrixSession';

export class MatrixSessionStore {
  save(session: MatrixSessionData): void {
    localStorage.setItem(KEY, JSON.stringify(session));
  }

  restore(): MatrixSessionData | null {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as MatrixSessionData) : null;
  }

  clear(): void {
    localStorage.removeItem(KEY);
  }
}
