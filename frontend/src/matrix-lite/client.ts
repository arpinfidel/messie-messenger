import type { LiteRoom, LiteMessage, LiteMember } from './types';
import { login as httpLogin, logout as httpLogout } from './api/auth';
import {
  joinedRooms,
  getRoomName,
  getRoomMembers as fetchRoomMembers,
  listJoinedRoomsWithNames,
} from './api/rooms';
import { roomMessages, sendRoomMessage, sendRoomEvent } from './api/messages';
import { getRoomPrevBatchToken } from './api/sync';
import { getBackupVersion, getBackupKeys } from './api/backup';
import { saveSession, loadSession, clearSession, type LiteSession } from './runtime/session';
import { startMiniSync } from './runtime/sync';
import {
  initCrypto as initOlmCrypto,
  handleSync as handleCryptoSync,
  importRoomKeys,
  decryptEvent,
  encryptEvent,
  drainOutgoingRequests,
  rotateMegolm as rotateMegolmEngine,
  getRoomSettingsSnapshot,
  getLastShareDebug,
} from './crypto/engine';
import { bootstrapCrossSigning as bootstrapCrossSigningEngine } from './crypto/engine';
import { importSecretsBundleFromJson } from './crypto/engine';
import { decodeRecoveryKey, deriveBackupKey, decryptBackupEntry } from './crypto/backup';
import {
  getDefaultSecretStorageKey,
  getSecret,
  getDefaultSecretStorageKeyFromAccountData,
  getSecretFromAccountData,
  fetchSSSSViaSync,
} from './api/secret_storage';
import { initAsync as initCryptoWasm, BackupDecryptionKey } from '@matrix-org/matrix-sdk-crypto-wasm';
import { isRoomEncrypted, getRoomEncryptionState, getRoomHistoryVisibility } from './api/rooms';
import { decryptSSSSSecretAESHMAC } from './crypto/ssss';
import { importCrossSigningKeys } from './crypto/engine';
import { getCrossSigningStatusSnapshot, getDeviceVerificationSnapshot, drainUntilIdle } from './crypto/engine';

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
  restoreBackupWithRecoveryKey(recoveryKey: string): Promise<number>;
  rotateMegolm(roomId: string): Promise<void>;
  getCryptoDebugInfo(roomId: string): Promise<any>;
  verifyWithRecoveryKey(recoveryKey: string): Promise<{ hasMaster: boolean; hasSelfSigning: boolean; hasUserSigning: boolean } | null>;
  bootstrapCrossSigning(reset?: boolean): Promise<boolean>;
  importSecretsBundleJson(json: any): Promise<boolean>;
  checkCrossSigningStatus(): Promise<{ status: any; device: any } | null>;
  publishSelfSignature(): Promise<{ ok: boolean; status: any; device: any } | null>;
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
    async restoreBackupWithRecoveryKey(_recoveryKey: string): Promise<number> {
      console.warn('[compat-mock] restoreBackupWithRecoveryKey() called');
      return 0;
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
      // Prefer a single /sync pass to gather names and avoid per-room 404s
      try {
        const rooms = await listJoinedRoomsWithNames(
          session.homeserverUrl,
          session.accessToken,
          session.userId
        );
        // Refine DM names to use bridged display names via room members
        const toRefine = rooms.filter((r) => {
          // If name equals room id, or looks like an mxid or a heroes-joined string, refine
          if (!r.name || r.name === r.id) return true;
          const looksLikeMxid = r.name.startsWith('@') && r.name.includes(':');
          const looksLikeAlias = r.name.startsWith('#') && r.name.includes(':');
          const inferredDM = (r.joinedCount === 2) || (r.heroes && r.heroes.length === 1);
          return inferredDM && (looksLikeMxid || looksLikeAlias);
        });

        const maxWorkers = Math.min(8, toRefine.length || 0);
        if (maxWorkers > 0) {
          let i = 0;
          const worker = async () => {
            while (true) {
              const idx = i++;
              if (idx >= toRefine.length) break;
              const rec = toRefine[idx];
              try {
                const members = await fetchRoomMembers(
                  session.homeserverUrl,
                  session.accessToken,
                  rec.id
                );
                const other = members.find((m) => m.userId !== session.userId);
                if (other && other.displayName) {
                  // Update in place
                  const target = rooms.find((x) => x.id === rec.id);
                  if (target) target.name = other.displayName;
                }
              } catch {}
            }
          };
          await Promise.all(new Array(maxWorkers).fill(0).map(() => worker()));
        }

        // Map to LiteRoom
        return rooms.map((r) => ({ id: r.id, name: r.name }));
      } catch (e) {
        console.warn('[matrix-lite] listRooms via /sync failed; falling back', e);
        // Fallback: joined room IDs then best-effort name lookups
        const ids = await joinedRooms(session.homeserverUrl, session.accessToken);
        const out: LiteRoom[] = [];
        for (const id of ids) {
          let name: string | undefined;
          try {
            name = await getRoomName(
              session.homeserverUrl,
              session.accessToken,
              id,
              session.userId
            );
          } catch {}
          out.push({ id, name: name || id });
        }
        return out;
      }
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
      let startToken: string | null | undefined = fromToken;
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
      const newMsgs: LiteMessage[] = [];
      if (Array.isArray(res.chunk)) {
        for (const ev of res.chunk) {
          if (ev?.type === 'm.room.message') {
            const body = ev.content?.body;
            const desc =
              typeof body === 'string'
                ? body
                : typeof ev.content?.msgtype === 'string'
                ? `[${ev.content.msgtype}]`
                : '';
            newMsgs.push({
              id: ev.event_id as string,
              roomId,
              sender: ev.sender as string,
              content: desc,
              timestamp: ev.origin_server_ts as number,
            });
          } else if (ev?.type === 'm.room.encrypted') {
            const dec = await decryptEvent(ev, roomId);
            if (dec?.type === 'm.room.message') {
              const body = dec.content?.body;
              const desc =
                typeof body === 'string'
                  ? body
                  : typeof dec.content?.msgtype === 'string'
                  ? `[${dec.content.msgtype}]`
                  : '';
              newMsgs.push({
                id: ev.event_id as string,
                roomId,
                sender: ev.sender as string,
                content: desc,
                timestamp: ev.origin_server_ts as number,
              });
            } else {
              newMsgs.push({
                id: ev.event_id as string,
                roomId,
                sender: ev.sender as string,
                content: 'Encrypted message',
                timestamp: ev.origin_server_ts as number,
              });
            }
          }
        }
      }
      newMsgs.sort((a, b) => a.timestamp - b.timestamp);
      return { messages: newMsgs, nextToken: res.end ?? null };
    },
    async sendMessage(roomId: string, content: string): Promise<LiteMessage> {
      const session = loadSession();
      if (!session) throw new Error('Not logged in');
      let eventId: string;
      try {
        const encrypted = await isRoomEncrypted(
          session.homeserverUrl,
          session.accessToken,
          roomId
        );
        console.log('[matrix-lite][debug] sendMessage path', { roomId, encrypted });
        if (encrypted) {
          const enc = await encryptEvent(roomId, 'm.room.message', {
            msgtype: 'm.text',
            body: content,
          });
          if (enc && enc.type === 'm.room.encrypted') {
            eventId = await sendRoomEvent(
              session.homeserverUrl,
              session.accessToken,
              roomId,
              enc.type,
              enc.content
            );
            // Best-effort: drain any pending crypto requests from sharing
            try { await drainOutgoingRequests(); } catch {}
            console.log('[matrix-lite][debug] sent encrypted message', { roomId, eventId });
          } else {
            // Fallback to plaintext if encryption failed
            eventId = await sendRoomMessage(
              session.homeserverUrl,
              session.accessToken,
              roomId,
              content
            );
            console.log('[matrix-lite][debug] encryption failed; sent plaintext', { roomId, eventId });
          }
        } else {
          // Plaintext room
          eventId = await sendRoomMessage(
            session.homeserverUrl,
            session.accessToken,
            roomId,
            content
          );
          console.log('[matrix-lite][debug] sent plaintext message', { roomId, eventId });
        }
      } catch (e) {
        console.warn('[matrix-lite] sendMessage encryption path failed; sending plaintext', e);
        eventId = await sendRoomMessage(
          session.homeserverUrl,
          session.accessToken,
          roomId,
          content
        );
        console.log('[matrix-lite][debug] sent plaintext due to error', { roomId, eventId });
      }
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
    async restoreBackupWithRecoveryKey(recoveryKey: string): Promise<number> {
      const session = loadSession();
      if (!session) return 0;
      const raw = decodeRecoveryKey(recoveryKey);
      const aesKey = await deriveBackupKey(raw);
      const version = await getBackupVersion(session.homeserverUrl, session.accessToken);
      console.log('[backup-restore] backup version info:', version);
      const data = await getBackupKeys(
        session.homeserverUrl,
        session.accessToken,
        version.version
      );
      const algo = String(version.algorithm || '');
      console.log('[backup-restore] algorithm:', algo);
      const toImport: any[] = [];
      let count = 0;
      if (/curve25519/i.test(algo)) {
        // Per spec/SDK: the Base58 recovery key is the 4S key, not the backup private key.
        // Always fetch the backup private key from SSSS using the recovery key.
        console.log('[backup-restore] using recovery key to fetch backup private key from SSSS');
        const viaSync = await fetchSSSSViaSync(session.homeserverUrl, session.accessToken);
        console.log('[ssss] via /sync present:', !!viaSync, 'has encrypted map:', !!viaSync?.encryptedByKeyId);
        let defaultKeyId = viaSync?.defaultKeyId;
        if (!defaultKeyId) {
          let def = await getDefaultSecretStorageKeyFromAccountData(
            session.homeserverUrl,
            session.accessToken,
            session.userId
          );
          defaultKeyId = def?.key;
        }
        console.log('[ssss] default key id:', defaultKeyId);
        let encByKey: Record<string, any> | undefined = viaSync?.encryptedByKeyId;
        if (!encByKey) {
          const secret = await getSecretFromAccountData(
            session.homeserverUrl,
            session.accessToken,
            session.userId,
            'm.megolm_backup.v1'
          );
          encByKey = (secret?.encrypted as Record<string, any>) || undefined;
        }
        console.log('[ssss] available secret key ids:', Object.keys(encByKey || {}));
        const encEntry = (defaultKeyId && encByKey ? encByKey[defaultKeyId] : undefined) || (encByKey ? Object.values(encByKey)[0] : undefined);
        if (!encEntry) {
          console.warn('[backup-restore] m.megolm_backup.v1 not found in SSSS; cannot proceed');
          return 0;
        }
        const ssssKey = raw; // The Base58 recovery key bytes
        const privBytes = await decryptSSSSSecretAESHMAC(encEntry, ssssKey, 'm.megolm_backup.v1');
        if (!privBytes) {
          console.warn('[backup-restore] Failed to decrypt backup private key from SSSS');
          return 0;
        }
        console.log('[ssss] decrypted backup key; bytes=', privBytes.length);

        // Build a BackupDecryptionKey and verify it matches the server backup public key
        await initCryptoWasm();
        const authPub = String((version?.auth_data as any)?.public_key || '');
        // privBytes may be base64 text or raw bytes; normalize to base64
        let keyB64: string;
        try {
          const asText = new TextDecoder().decode(privBytes).trim();
          keyB64 = asText;
        } catch {
          keyB64 = '';
        }
        if (!/^[-A-Za-z0-9+/=]+$/.test(keyB64) || keyB64.length < 40) {
          // encode raw 32 bytes to base64
          let s = '';
          for (let i = 0; i < privBytes.length; i++) s += String.fromCharCode(privBytes[i]);
          keyB64 = btoa(s);
        }
        // @ts-ignore wasm type
        const decKey = (BackupDecryptionKey as any).fromBase64(keyB64);
        let derivedPub = '';
        try {
          // @ts-ignore wasm prop
          derivedPub = decKey.megolmV1PublicKey?.publicKeyBase64 || '';
        } catch {}
        console.log('[backup-restore] server pubKey:', authPub, 'derived pubKey:', derivedPub);
        if (!authPub || !derivedPub || authPub !== derivedPub) {
          console.warn('[backup-restore] backup private key does not match server backup public key');
          try { decKey.free?.(); } catch {}
          return 0;
        }
        const rooms = data?.rooms ?? {};
        console.log('[backup-restore] rooms in backup:', Object.keys(rooms).length);
        const padB64 = (s: string) => {
          const t = s.replace(/\s+/g, '');
          const rem = t.length % 4;
          return rem === 0 ? t : t + '='.repeat(4 - rem);
        };
        for (const [roomId, roomVal] of Object.entries(rooms as any)) {
          const sessions = (roomVal as any)?.sessions ?? {};
          const sessionIds = Object.keys(sessions || {});
          if (sessionIds.length === 0) continue;
          console.log('[backup-restore] sessions in room:', sessionIds.length);
          for (const [sessionId, sess] of Object.entries(sessions as any)) {
            const sd: any = (sess as any)?.session_data || {};
            const e: string | undefined = sd.ephemeral;
            const m: string | undefined = sd.mac;
            const c: string | undefined = sd.ciphertext;
            if (!e || !m || !c) {
              console.warn('[backup-restore] missing fields for session', sessionId, {
                hasE: !!e,
                hasM: !!m,
                hasC: !!c,
              });
              continue;
            }
            try {
              // @ts-ignore
              const json = decKey.decryptV1(padB64(e), padB64(m), padB64(c));
              const dec = JSON.parse(json);
              (dec as any).session_id = sessionId;
              (dec as any).room_id = roomId;
              toImport.push(dec);
              count++;
            } catch (err) {
              const msg = (err as any)?.message || String(err);
              console.warn('[backup-restore] decryptV1 failed for session', sessionId, msg);
            }
          }
        }
        try { decKey.free?.(); } catch {}
      } else {
        const rooms = data?.rooms ?? {};
        console.log('[backup-restore] rooms in backup:', Object.keys(rooms).length);
        for (const [roomId, roomVal] of Object.entries(rooms as any)) {
          const sessions = (roomVal as any)?.sessions ?? {};
          const sessionIds = Object.keys(sessions || {});
          if (sessionIds.length === 0) continue;
          console.log('[backup-restore] sessions in room:', sessionIds.length);
          // Log the shape of the first session entry for debugging (no secrets)
          try {
            const first = (sessions as any)[sessionIds[0]];
            if (first && typeof first === 'object') {
              const keys = Object.keys(first || {}).slice(0, 10);
              const payloadKeys = first?.session_data ? Object.keys(first.session_data).slice(0, 10) : [];
              console.log('[backup-restore] sample session keys:', keys, 'session_data keys:', payloadKeys);
            }
          } catch {}
          for (const [sessionId, sess] of Object.entries(sessions as any)) {
            const dec = await decryptBackupEntry(sess, aesKey, algo);
            if (dec) {
              (dec as any).session_id = sessionId;
              (dec as any).room_id = roomId;
              toImport.push(dec);
              count++;
            }
          }
        }
      }
      if (toImport.length > 0) {
        await importRoomKeys(toImport);
      }
      console.log(`[backup-restore] Imported ${count} sessions`);
      return count;
    },
    async rotateMegolm(roomId: string): Promise<void> {
      await rotateMegolmEngine(roomId);
    },
    async getCryptoDebugInfo(roomId: string): Promise<any> {
      const session = loadSession();
      if (!session) return null;
      const [encState, hist, settings, lastShare] = await Promise.all([
        getRoomEncryptionState(session.homeserverUrl, session.accessToken, roomId).catch(() => null),
        getRoomHistoryVisibility(session.homeserverUrl, session.accessToken, roomId).catch(() => undefined),
        getRoomSettingsSnapshot(roomId).catch(() => null),
        Promise.resolve(getLastShareDebug(roomId)),
      ]);
      return {
        roomId,
        encryptionState: encState,
        historyVisibility: hist,
        roomSettings: settings,
        lastShare,
      };
    },
    async verifyWithRecoveryKey(recoveryKey: string): Promise<{ imported: boolean; statusBefore: any; statusAfter: any; deviceVerified: boolean } | null> {
      const session = loadSession();
      if (!session) return null;
      const raw = decodeRecoveryKey(recoveryKey);
      // Determine default SSSS key id from account data (SDK does this)
      let defaultKeyId: string | undefined;
      const def = await getDefaultSecretStorageKeyFromAccountData(
        session.homeserverUrl,
        session.accessToken,
        session.userId
      );
      defaultKeyId = def?.key;
      if (!defaultKeyId) {
        const via = await fetchSSSSViaSync(session.homeserverUrl, session.accessToken);
        defaultKeyId = via?.defaultKeyId;
      }
      const get = async (name: string): Promise<string | null> => {
        try {
          // Fetch secret from account data (SDK stores secrets under their name)
          const secret = await getSecretFromAccountData(
            session.homeserverUrl,
            session.accessToken,
            session.userId,
            name
          );
          const encByKey = (secret?.encrypted as Record<string, any>) || undefined;
          if (!encByKey || typeof encByKey !== 'object') return null;
          // Try default key id first, then all others
          const order: any[] = [];
          if (defaultKeyId && encByKey[defaultKeyId]) order.push(encByKey[defaultKeyId]);
          for (const v of Object.values(encByKey)) order.push(v);
          for (const encEntry of order) {
            if (!encEntry) continue;
            const bytes = await decryptSSSSSecretAESHMAC(encEntry, raw, name);
            if (bytes) {
              try { return new TextDecoder().decode(bytes).trim(); } catch { return null; }
            }
          }
          return null;
        } catch { return null; }
      };
      const master = await get('m.cross_signing.master');
      const selfS = await get('m.cross_signing.self_signing');
      const userS = await get('m.cross_signing.user_signing');
      if (!master && !selfS && !userS) {
        console.warn('[matrix-lite] No cross-signing secrets found in SSSS');
        return null;
      }
      const statusBefore = await getCrossSigningStatusSnapshot();
      const importRes = await importCrossSigningKeys({ master, selfSigning: selfS, userSigning: userS });
      // Drain outgoing (including SignatureUpload) until idle
      await drainUntilIdle(6);
      const statusAfter = await getCrossSigningStatusSnapshot();
      const device = await getDeviceVerificationSnapshot(session.userId, session.deviceId);
      return {
        imported: !!importRes,
        statusBefore,
        statusAfter,
        deviceVerified: !!device?.verified,
      };
    },
    async checkCrossSigningStatus(): Promise<{ status: any; device: any } | null> {
      const session = loadSession();
      if (!session) return null;
      const status = await getCrossSigningStatusSnapshot();
      const device = await getDeviceVerificationSnapshot(session.userId, session.deviceId);
      return { status, device };
    },
    async publishSelfSignature(): Promise<{ ok: boolean; status: any; device: any } | null> {
      const session = loadSession();
      if (!session) return null;
      const ok = await bootstrapCrossSigningEngine(false);
      await drainUntilIdle(6);
      const status = await getCrossSigningStatusSnapshot();
      const device = await getDeviceVerificationSnapshot(session.userId, session.deviceId);
      return { ok, status, device };
    },
    async bootstrapCrossSigning(reset = false): Promise<boolean> {
      return bootstrapCrossSigningEngine(reset);
    },
    async importSecretsBundleJson(json: any): Promise<boolean> {
      return importSecretsBundleFromJson(json);
    },
  };
}

// Expose concise, non-spammy debug helpers on window for interactive use
// Usage from DevTools:
//   await window.__matrixLiteDebug.snapshotSSSS()
//   await window.__matrixLiteDebug.testDecryptWithRecoveryKey('<recovery key>')
//   await window.__matrixLiteDebug.getCryptoDebugInfo('<roomId>')
//   await window.__matrixLiteDebug.rotateMegolm('<roomId>')
try {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const w: any = (globalThis as any)?.window || (globalThis as any);
  if (w && !w.__matrixLiteDebug) {
    // Local, shared helpers
    const snapshotSSSS = async () => {
      const session = loadSession();
      if (!session) return { error: 'not_logged_in' };
      const { homeserverUrl, accessToken, userId } = session;
      let defaultKeyId: string | undefined;
      try {
        const def = await getDefaultSecretStorageKeyFromAccountData(homeserverUrl, accessToken, userId);
        defaultKeyId = def?.key;
      } catch {}
      if (!defaultKeyId) {
        try { defaultKeyId = (await fetchSSSSViaSync(homeserverUrl, accessToken))?.defaultKeyId; } catch {}
      }
      const names = [
        'm.cross_signing.master',
        'm.cross_signing.self_signing',
        'm.cross_signing.user_signing',
        'm.megolm_backup.v1',
      ];
      const secrets: Record<string, { present: boolean; keyIds: string[] }> = {} as any;
      for (const n of names) {
        try {
          const ev = await getSecretFromAccountData(homeserverUrl, accessToken, userId, n);
          const enc = (ev?.encrypted as Record<string, any>) || {};
          secrets[n] = { present: Object.keys(enc).length > 0, keyIds: Object.keys(enc) };
        } catch {
          secrets[n] = { present: false, keyIds: [] } as any;
        }
      }
      return { defaultKeyId, secrets };
    };

    const testDecryptWithRecoveryKey = async (recoveryKey: string) => {
      const session = loadSession();
      if (!session) return { error: 'not_logged_in' };
      const { homeserverUrl, accessToken, userId } = session;
      let defaultKeyId: string | undefined;
      try {
        const def = await getDefaultSecretStorageKeyFromAccountData(homeserverUrl, accessToken, userId);
        defaultKeyId = def?.key;
      } catch {}
      if (!defaultKeyId) {
        try { defaultKeyId = (await fetchSSSSViaSync(homeserverUrl, accessToken))?.defaultKeyId; } catch {}
      }
      let raw: Uint8Array | null = null;
      try { raw = decodeRecoveryKey(recoveryKey); } catch (e) { return { error: 'bad_recovery_key', message: String(e) }; }

      const names = ['m.cross_signing.master', 'm.cross_signing.self_signing', 'm.cross_signing.user_signing'];
      const attempts: Record<string, { tried: string[]; ok: boolean }> = {} as any;
      for (const name of names) {
        attempts[name] = { tried: [], ok: false } as any;
        try {
          const ev = await getSecretFromAccountData(homeserverUrl, accessToken, userId, name);
          const enc = (ev?.encrypted as Record<string, any>) || {};
          const keyOrder: any[] = [];
          if (defaultKeyId && enc[defaultKeyId]) keyOrder.push({ id: defaultKeyId, payload: enc[defaultKeyId] });
          for (const [id, payload] of Object.entries(enc)) keyOrder.push({ id, payload });
          for (const entry of keyOrder) {
            if (!entry?.payload) continue;
            attempts[name].tried.push(entry.id as string);
            try {
              const bytes = await decryptSSSSSecretAESHMAC(entry.payload, raw!, name);
              if (bytes) { attempts[name].ok = true; break; }
            } catch {}
          }
        } catch {}
      }
      return { defaultKeyId, attempts };
    };

    w.__matrixLiteDebug = {
      snapshotSSSS,
      testDecryptWithRecoveryKey,
      // Wire through methods when a real client exists (after login)
      getCryptoDebugInfo: async (roomId: string) => {
        try {
          const vmMod = await import('../viewmodels/matrix');
          const vm: any = vmMod.MatrixViewModel.getInstance();
          const client: any = vm?.client ?? vm;
          return client?.getCryptoDebugInfo ? client.getCryptoDebugInfo(roomId) : null;
        } catch { return null; }
      },
      rotateMegolm: async (roomId: string) => {
        try {
          const vmMod = await import('../viewmodels/matrix');
          const vm: any = vmMod.MatrixViewModel.getInstance();
          const client: any = vm?.client ?? vm;
          return client?.rotateMegolm ? client.rotateMegolm(roomId) : null;
        } catch { return null; }
      },
    };
  }
} catch {}
