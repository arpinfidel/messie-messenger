import type { LiteRoom, LiteMessage, LiteMember } from './types';
import { login as httpLogin, logout as httpLogout } from './api/auth';
import { joinedRooms, getRoomName, getRoomMembers as fetchRoomMembers } from './api/rooms';
import { roomMessages, sendRoomMessage } from './api/messages';
import { getRoomPrevBatchToken } from './api/sync';
import { saveSession, loadSession, clearSession, type LiteSession } from './runtime/session';
import { startMiniSync } from './runtime/sync';
import {
  initCrypto as initOlmCrypto,
  handleSync as handleCryptoSync,
} from './crypto/engine';

/**
 * Public interface for the lightweight Matrix client.
 * Internals can swap between mock and real implementations
 * without affecting consumers.
 */
export interface MatrixLiteClient {
  login(username: string, password: string): Promise<void>;
  logout(): Promise<void>;
  listRooms(): Promise<LiteRoom[]>;
  getRoomMessages(
    roomId: string,
    fromToken?: string,
    limit?: number
  ): Promise<{ messages: LiteMessage[]; nextToken: string | null }>;
  sendMessage(roomId: string, content: string): Promise<LiteMessage>;
  getRoomMembers(roomId: string): Promise<LiteMember[]>;
  onToDevice(cb: (ev: any) => void): () => void;
  isSyncing(): boolean;
  initCrypto(): Promise<void>;
}

/**
 * Create a MatrixLiteClient backed by in-memory mock data.
 * Every call prints a `[compat-mock]` warning to highlight
 * that fake data is being used.
 */
export function createMockClient(suppressLog = false): MatrixLiteClient {
  if (!suppressLog) {
    console.warn('[compat-mock] Using mock Matrix Lite client');
  }

  const userId = '@alice:example.org';
  const rooms: Array<{
    room: LiteRoom;
    messages: LiteMessage[];
    members: LiteMember[];
  }> = [
    {
      room: { id: '!room1:example.org', name: 'General' },
      messages: [
        {
          id: '$msg1',
          roomId: '!room1:example.org',
          sender: '@alice:example.org',
          content: 'Welcome to the General room',
          timestamp: Date.now() - 60000,
        },
        {
          id: '$msg2',
          roomId: '!room1:example.org',
          sender: '@bob:example.org',
          content: 'Hello everyone!',
          timestamp: Date.now() - 30000,
        },
      ],
      members: [
        { userId: '@alice:example.org', displayName: 'Alice' },
        { userId: '@bob:example.org', displayName: 'Bob' },
      ],
    },
    {
      room: { id: '!room2:example.org', name: 'Random' },
      messages: [
        {
          id: '$msg3',
          roomId: '!room2:example.org',
          sender: '@carol:example.org',
          content: 'Random chatter goes here',
          timestamp: Date.now() - 50000,
        },
      ],
      members: [
        { userId: '@carol:example.org', displayName: 'Carol' },
        { userId: '@dave:example.org', displayName: 'Dave' },
      ],
    },
  ];

  return {
    async login(_username: string, _password: string): Promise<void> {
      console.warn('[compat-mock] login() called');
    },
    async logout(): Promise<void> {
      console.warn('[compat-mock] logout() called');
    },
    async listRooms(): Promise<LiteRoom[]> {
      console.warn('[compat-mock] listRooms() called');
      return rooms.map((r) => r.room);
    },
    async getRoomMessages(
      roomId: string,
      _fromToken?: string,
      _limit = 20
    ): Promise<{ messages: LiteMessage[]; nextToken: string | null }> {
      console.warn('[compat-mock] getRoomMessages() called');
      // For mock, return everything without pagination and indicate no more.
      const all = rooms.find((r) => r.room.id === roomId)?.messages ?? [];
      return { messages: all, nextToken: null };
    },
    async sendMessage(roomId: string, content: string): Promise<LiteMessage> {
      console.warn('[compat-mock] sendMessage() called');
      const room = rooms.find((r) => r.room.id === roomId);
      if (!room) throw new Error('Room not found');
      const msg: LiteMessage = {
        id: `$msg${Math.random().toString(36).slice(2)}`,
        roomId,
        sender: userId,
        content,
        timestamp: Date.now(),
      };
      room.messages.push(msg);
      return msg;
    },
    async getRoomMembers(roomId: string): Promise<LiteMember[]> {
      console.warn('[compat-mock] getRoomMembers() called');
      return rooms.find((r) => r.room.id === roomId)?.members ?? [];
    },
    onToDevice(cb: (ev: any) => void): () => void {
      console.warn('[compat-mock] onToDevice() called');
      // Immediately invoke with a mock event so consumers can test wiring
      try {
        cb({ type: 'm.mock', content: {} });
      } catch {}
      return () => {};
    },
    isSyncing(): boolean {
      return false;
    },
    async initCrypto(): Promise<void> {
      console.warn('[compat-mock] initCrypto() called');
    },
  };
}

/**
 * Create a MatrixLiteClient that performs real login/logout calls
 * and fetches real joined rooms and messages, while reusing mock
 * implementations for member lookups.
 */
export function createClient(homeserverUrl: string): MatrixLiteClient {
  // Reuse mock implementations internally without logging to avoid confusion
  const mock = createMockClient(true);
  const toDeviceListeners = new Set<(ev: any) => void>();
  let stopSync: (() => void) | null = null;

  function emit(ev: any): void {
    console.log('[matrix-lite] to-device event', ev);
    for (const l of toDeviceListeners) {
      try {
        l(ev);
      } catch (err) {
        console.error(err);
      }
    }
  }

  function startSync(): void {
    if (stopSync) return;
    const session = loadSession();
    if (!session) return;
    stopSync = startMiniSync(
      session.homeserverUrl,
      session.accessToken,
      emit,
      handleCryptoSync
    );
  }

  function stopSyncLoop(): void {
    if (stopSync) {
      stopSync();
      stopSync = null;
    }
  }
  return {
    ...mock,
    async login(username: string, password: string): Promise<void> {
      const session = await httpLogin(homeserverUrl, username, password);
      saveSession(session);
      // Initialize crypto right after login so device keys can upload
      try {
        await initOlmCrypto(session.userId, session.deviceId);
      } catch (err) {
        console.warn('[matrix-lite] initCrypto after login failed', err);
      }
      startSync();
    },
    async logout(): Promise<void> {
      const session: LiteSession | null = loadSession();
      if (session) {
        try {
          await httpLogout(session.homeserverUrl, session.accessToken);
        } finally {
          clearSession();
        }
      }
      stopSyncLoop();
    },
    async listRooms(): Promise<LiteRoom[]> {
      const session = loadSession();
      if (!session) return [];
      // Fetch joined room IDs first
      const ids = await joinedRooms(session.homeserverUrl, session.accessToken);

      // Resolve room names with limited concurrency (10 workers)
      const maxWorkers = Math.min(10, ids.length || 0);
      if (maxWorkers === 0) return [];

      const out: LiteRoom[] = new Array(ids.length);
      let i = 0;
      const worker = async () => {
        while (true) {
          const idx = i++;
          if (idx >= ids.length) break;
          const id = ids[idx];
          try {
            const name =
              (await getRoomName(session.homeserverUrl, session.accessToken, id)) || id;
            out[idx] = { id, name };
          } catch {
            out[idx] = { id, name: id };
          }
        }
      };
      await Promise.all(new Array(maxWorkers).fill(0).map(() => worker()));
      return out.filter(Boolean);
    },
    async getRoomMessages(
      roomId: string,
      fromToken?: string,
      limit = 20
    ): Promise<{ messages: LiteMessage[]; nextToken: string | null }> {
      const session = loadSession();
      if (!session) return { messages: [], nextToken: null };
      // If no token provided, try to obtain a real prev_batch via /sync to support servers
      // that don't implement from=END properly (commonly seen with some bridged rooms).
      let startToken = fromToken;
      if (!startToken) {
        try {
          startToken = await getRoomPrevBatchToken(
            session.homeserverUrl,
            session.accessToken,
            roomId
          );
        } catch {}
      }
      const res = await roomMessages(
        session.homeserverUrl,
        session.accessToken,
        roomId,
        startToken || fromToken || 'END',
        limit
      );
      const newMsgs: LiteMessage[] = Array.isArray(res.chunk)
        ? res.chunk
            .filter((ev: any) =>
              ev?.type === 'm.room.message' || ev?.type === 'm.room.encrypted'
            )
            .map((ev: any) => {
              if (ev.type === 'm.room.message') {
                const body = ev.content?.body;
                // Fallback to msgtype description if body is missing but msgtype present
                const desc =
                  typeof body === 'string'
                    ? body
                    : typeof ev.content?.msgtype === 'string'
                    ? `[${ev.content.msgtype}]`
                    : '';
                return {
                  id: ev.event_id as string,
                  roomId,
                  sender: ev.sender as string,
                  content: desc,
                  timestamp: ev.origin_server_ts as number,
                } as LiteMessage;
              }
              // Encrypted event: show placeholder so it appears in timeline
              return {
                id: ev.event_id as string,
                roomId,
                sender: ev.sender as string,
                content: 'Encrypted message',
                timestamp: ev.origin_server_ts as number,
              } as LiteMessage;
            })
        : [];
      return { messages: newMsgs, nextToken: res.end ?? null };
    },
    async sendMessage(roomId: string, content: string): Promise<LiteMessage> {
      const session = loadSession();
      if (!session) throw new Error('Not logged in');
      const eventId = await sendRoomMessage(
        session.homeserverUrl,
        session.accessToken,
        roomId,
        content
      );
      const msg: LiteMessage = {
        id: eventId,
        roomId,
        sender: session.userId,
        content,
        timestamp: Date.now(),
      };
      return msg;
    },
    async getRoomMembers(roomId: string): Promise<LiteMember[]> {
      const session = loadSession();
      if (!session) return [];
      try {
        const members = await fetchRoomMembers(
          session.homeserverUrl,
          session.accessToken,
          roomId
        );
        // The API already maps to LiteMember shape; return as-is.
        return members.map((m) => ({
          userId: m.userId,
          displayName: m.displayName,
          avatarUrl: m.avatarUrl,
        }));
      } catch (e) {
        console.warn('[matrix-lite] getRoomMembers failed', e);
        return [];
      }
    },
    onToDevice(cb: (ev: any) => void): () => void {
      toDeviceListeners.add(cb);
      startSync();
      return () => toDeviceListeners.delete(cb);
    },
    isSyncing(): boolean {
      return !!stopSync;
    },
    async initCrypto(): Promise<void> {
      const session = loadSession();
      if (!session) return;
      await initOlmCrypto(session.userId, session.deviceId);
      startSync();
    },
  };
}
