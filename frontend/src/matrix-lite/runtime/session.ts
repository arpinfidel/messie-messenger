export interface LiteSession {
  homeserverUrl: string;
  accessToken: string;
  userId: string;
  deviceId: string;
}

const STORAGE_KEY = 'matrix-lite-session';

export function saveSession(session: LiteSession): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
}

export function loadSession(): LiteSession | null {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as LiteSession;
  } catch {
    return null;
  }
}

export function clearSession(): void {
  localStorage.removeItem(STORAGE_KEY);
}
