import {
  initAsync,
  OlmMachine,
  UserId,
  DeviceId,
  DeviceLists,
  RoomId,
  DecryptionSettings,
  EncryptionSettings,
  CollectStrategy,
  RoomSettings,
  EncryptionAlgorithm,
  HistoryVisibility,
  TrustRequirement,
} from '@matrix-org/matrix-sdk-crypto-wasm';
import { loadSession } from '../runtime/session';
import { keysUpload, keysQuery, keysClaim } from '../api/keys';
import { uploadSignatures } from '../api/signatures';
import { sendToDevice } from '../api/to_device';
import { RequestType } from '@matrix-org/matrix-sdk-crypto-wasm';
import { getRoomMembers, getRoomEncryptionState, getRoomHistoryVisibility, joinedRooms } from '../api/rooms';

let machine: OlmMachine | null = null;
let debugLoggedProto = false;
let draining = false;
const lastShareByRoom = new Map<string, { eventType: string; userCount: number; deviceCount: number; sampleUsers: string[]; rotated?: boolean; ts: number }>();
const roomShareLocks = new Map<string, Promise<void>>();

async function withRoomShareLock(roomId: string, fn: () => Promise<void>): Promise<void> {
  const prev = roomShareLocks.get(roomId) || Promise.resolve();
  let release: (v?: void) => void;
  const p = new Promise<void>((res) => (release = res));
  roomShareLocks.set(roomId, prev.then(async () => {
    try { await fn(); } finally { release!(); }
  }));
  await roomShareLocks.get(roomId);
}

export async function initCrypto(userId: string, deviceId: string): Promise<void> {
  if (machine) return;
  await initAsync();
  machine = await OlmMachine.initialize(new UserId(userId), new DeviceId(deviceId));
  console.log('[matrix-lite] crypto engine initialized');
  // Enable automatic room key requests and forwarding so missed keys can be recovered/gossiped
  try {
    // @ts-ignore feature flags on wasm binding
    (machine as any).roomKeyRequestsEnabled = true;
    // @ts-ignore feature flags on wasm binding
    (machine as any).roomKeyForwardingEnabled = true;
  } catch {}
  // After init, fulfill any outgoing requests (e.g., upload device keys)
  try {
    await drainOutgoingRequests();
  } catch (err) {
    console.warn('[matrix-lite] drain after init failed', err);
  }
}

export function getOlmMachine(): OlmMachine | null {
  return machine;
}

/** Snapshot the engine's RoomSettings for a room (if any). */
export async function getRoomSettingsSnapshot(roomId: string): Promise<{
  algorithm?: string;
  onlyAllowTrustedDevices?: boolean;
  sessionRotationPeriodMs?: number;
  sessionRotationPeriodMessages?: number;
} | null> {
  if (!machine) return null;
  try {
    // @ts-ignore wasm types
    const rs: any = await (machine as any).getRoomSettings(new RoomId(roomId));
    if (!rs) return null;
    const out: any = {};
    try { out.algorithm = String(rs.algorithm); } catch {}
    try { out.onlyAllowTrustedDevices = !!rs.onlyAllowTrustedDevices; } catch {}
    try { out.sessionRotationPeriodMs = rs.sessionRotationPeriodMs; } catch {}
    try { out.sessionRotationPeriodMessages = rs.sessionRotationPeriodMessages; } catch {}
    try { rs.free?.(); } catch {}
    return out;
  } catch (e) {
    return null;
  }
}

/** Last to-device share debug for a room (if any) */
export function getLastShareDebug(roomId: string): { eventType: string; userCount: number; deviceCount: number; sampleUsers: string[]; rotated?: boolean; ts: number } | null {
  return lastShareByRoom.get(roomId) ?? null;
}

export async function importCrossSigningKeys(opts: {
  master?: string | null;
  selfSigning?: string | null;
  userSigning?: string | null;
}): Promise<{ hasMaster: boolean; hasSelfSigning: boolean; hasUserSigning: boolean } | null> {
  if (!machine) return null;
  try {
    const m: any = machine as any;
    const status: any = await m.importCrossSigningKeys(
      opts.master ?? null,
      opts.selfSigning ?? null,
      opts.userSigning ?? null
    );
    // status has methods hasMaster/hasSelfSigning/hasUserSigning on wasm type
    const out = {
      hasMaster: false,
      hasSelfSigning: false,
      hasUserSigning: false,
    };
    try { out.hasMaster = !!status?.hasMaster?.(); } catch {}
    try { out.hasSelfSigning = !!status?.hasSelfSigning?.(); } catch {}
    try { out.hasUserSigning = !!status?.hasUserSigning?.(); } catch {}
    try { status?.free?.(); } catch {}
    return out;
  } catch (e) {
    console.warn('[matrix-lite] importCrossSigningKeys failed', e);
    return null;
  }
}

/** Create a new cross-signing identity for this account/device and upload signatures. */
export async function bootstrapCrossSigning(reset = false): Promise<boolean> {
  if (!machine) return false;
  try {
    // @ts-ignore wasm types
    const reqs = await (machine as any).bootstrapCrossSigning(!!reset);
    try { reqs?.free?.(); } catch {}
    // Drain any outgoing requests generated (keys upload and signature upload)
    await drainOutgoingRequests();
    return true;
  } catch (e) {
    console.warn('[matrix-lite] bootstrapCrossSigning failed', e);
    return false;
  }
}

/** Get current cross-signing status booleans from engine. */
export async function getCrossSigningStatusSnapshot(): Promise<{ hasMaster: boolean; hasSelfSigning: boolean; hasUserSigning: boolean } | null> {
  if (!machine) return null;
  try {
    const m: any = machine as any;
    const status: any = await m.crossSigningStatus();
    const out = { hasMaster: false, hasSelfSigning: false, hasUserSigning: false };
    try { out.hasMaster = !!status?.hasMaster?.(); } catch {}
    try { out.hasSelfSigning = !!status?.hasSelfSigning?.(); } catch {}
    try { out.hasUserSigning = !!status?.hasUserSigning?.(); } catch {}
    try { status?.free?.(); } catch {}
    return out;
  } catch (e) {
    console.warn('[matrix-lite] crossSigningStatus failed', e);
    return null;
  }
}

/** Get verification snapshot for a specific device. */
export async function getDeviceVerificationSnapshot(userId: string, deviceId: string): Promise<{
  verified?: boolean;
  locallyTrusted?: boolean;
  crossSigningTrusted?: boolean;
  blacklisted?: boolean;
} | null> {
  if (!machine) return null;
  try {
    const dev: any = await (machine as any).getDevice(new UserId(userId), new DeviceId(deviceId));
    if (!dev) return null;
    const out = {
      verified: false,
      locallyTrusted: false,
      crossSigningTrusted: false,
      blacklisted: false,
    };
    try { out.verified = !!dev.isVerified?.(); } catch {}
    try { out.locallyTrusted = !!dev.isLocallyTrusted?.(); } catch {}
    try { out.crossSigningTrusted = !!dev.isCrossSigningTrusted?.(); } catch {}
    try { out.blacklisted = !!dev.isBlacklisted?.(); } catch {}
    try { dev.free?.(); } catch {}
    return out;
  } catch (e) {
    console.warn('[matrix-lite] getDeviceVerificationSnapshot failed', e);
    return null;
  }
}

/** Drain outgoing requests multiple times until idle, with a max pass safety. */
export async function drainUntilIdle(maxPasses = 5): Promise<number> {
  let passes = 0;
  for (; passes < maxPasses; passes++) {
    await drainOutgoingRequests();
    // Heuristic: try to see if there are requests left
    let reqs: any[] = [];
    try { reqs = await (machine as any)?.outgoingRequests?.(); } catch { reqs = []; }
    if (!Array.isArray(reqs) || reqs.length === 0) break;
  }
  return passes;
}

/** Import a SecretsBundle JSON exported from another verified device. */
export async function importSecretsBundleFromJson(json: any): Promise<boolean> {
  if (!machine) return false;
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const wasm = require('@matrix-org/matrix-sdk-crypto-wasm');
    const bundle = wasm.SecretsBundle.from_json(json);
    const m: any = machine as any;
    await m.importSecretsBundle(bundle);
    try { bundle.free?.(); } catch {}
    await drainOutgoingRequests();
    return true;
  } catch (e) {
    console.warn('[matrix-lite] importSecretsBundleFromJson failed', e);
    return false;
  }
}

export async function handleSync(data: any): Promise<any[]> {
  if (!machine || !data) return [];
  try {
    const toDevice = JSON.stringify(data.to_device?.events || []);
    try {
      const tdCount = Array.isArray(data.to_device?.events) ? data.to_device.events.length : 0;
      const changedCount = Array.isArray(data.device_lists?.changed) ? data.device_lists.changed.length : 0;
      console.log('[matrix-lite][debug] handleSync', { toDeviceCount: tdCount, changedCount });
    } catch {}
    const changedRaw: string[] = Array.isArray(data.device_lists?.changed) ? data.device_lists.changed : [];
    const leftRaw: string[] = Array.isArray(data.device_lists?.left) ? data.device_lists.left : [];
    const changed = changedRaw.map((u: string) => new UserId(u));
    const left = leftRaw.map((u: string) => new UserId(u));
    const deviceLists = new DeviceLists(changed, left);
    const otk = new Map<string, number>();
    const counts = data.device_one_time_keys_count as Record<string, number> | undefined;
    if (counts) {
      for (const [k, v] of Object.entries(counts)) {
        otk.set(k, v);
      }
    }
    const unused = Array.isArray(data.device_unused_fallback_key_types)
      ? new Set<string>(data.device_unused_fallback_key_types)
      : undefined;
    // @ts-ignore wasm types
    const processed: any[] = await (machine as any).receiveSyncChanges(
      toDevice,
      deviceLists,
      otk,
      unused
    );
    // Receiving sync may create outgoing requests (query/claim keys); drain them
    await drainOutgoingRequests();
    const out: any[] = [];
    for (const p of processed || []) {
      try {
        const raw: string | undefined = (p as any)?.event || (p as any)?.rawEvent;
        if (typeof raw === 'string') {
          out.push(JSON.parse(raw));
        }
      } catch {}
    }
    // Proactively (re)share keys to rooms where members' device lists changed
    if (changedRaw.length > 0) {
      try {
        await processDeviceListChanges(changedRaw);
      } catch (e) {
        console.warn('[matrix-lite] processDeviceListChanges failed', e);
      }
    }
    return out;
  } catch (err) {
    console.warn('[matrix-lite] crypto sync error', err);
    return [];
  }
}

/**
 * Drain and fulfill outgoing requests from the crypto engine.
 * Handles device key upload, query, and claim.
 */
export async function drainOutgoingRequests(): Promise<void> {
  if (!machine) return;
  const session = loadSession();
  if (!session) return;
  const { homeserverUrl, accessToken } = session;
  if (draining) return; // prevent concurrent drains
  draining = true;
  try {

  // Loop until no more requests remain
  // Some requests generate follow-up requests that should be processed immediately.
  for (;;) {
    let requests: any[] = [];
    try {
      // @ts-ignore - wasm types may not be available at build-time here
      requests = (await (machine as any).outgoingRequests()) as any[];
    } catch (err) {
      console.warn('[matrix-lite] failed to fetch outgoing crypto requests', err);
      return;
    }
    if (!Array.isArray(requests) || requests.length === 0) return;

    let completed = 0;
    let malformed = 0;
    const warnedIds = new Set<string>();
    let debugCount = 0;
    for (const req of requests) {
      // Accessors: prefer fields, fall back to calling if functions
      const getField = (o: any, names: string[]): any => {
        for (const n of names) {
          try {
            const v = o?.[n];
            if (v === undefined) continue;
            if (typeof v === 'function') {
              return v.call(o);
            }
            return v;
          } catch {}
        }
        return undefined;
      };

      let id: string | undefined = getField(req, ['id', 'requestId', 'request_id']);
      let typeVal: RequestType | number | string | undefined = getField(req, [
        'type',
        'requestType',
        'kind',
      ]);
      let bodyRawAny: any = getField(req, ['body', 'json', 'request']);

      // Best-effort coercion
      if (id && typeof id !== 'string' && typeof (id as any).toString === 'function') id = String(id);
        let typeRaw: any =
          typeof typeVal === 'number' || typeof typeVal === 'string'
            ? typeVal
            : typeVal && typeof (typeVal as any).toString === 'function'
            ? String(typeVal)
            : undefined;
      let body: any = {};
      if (typeof bodyRawAny === 'string' && bodyRawAny.length > 0) {
        try {
          body = JSON.parse(bodyRawAny);
        } catch {
          body = {};
        }
      } else if (bodyRawAny && typeof bodyRawAny === 'object') {
        body = bodyRawAny;
      }
      if (debugCount < 1) {
        console.log('[matrix-lite] outgoing request snapshot', {
          idType: typeof id,
          typeType: typeof typeVal,
          typeVal,
          hasBody: !!body && Object.keys(body || {}).length > 0,
        });
        debugCount++;
      }
      // Heuristic: infer type from body shape if wasm enum not available
      if (typeRaw === undefined || typeRaw === null) {
        try {
          if (body && typeof body === 'object') {
            if (body.device_keys && typeof body.device_keys === 'object') {
              if (typeof body.device_keys.user_id === 'string') {
                typeRaw = 'KeysUpload';
              } else {
                typeRaw = 'KeysQuery';
              }
            } else if (body.one_time_keys && typeof body.one_time_keys === 'object') {
              typeRaw = 'KeysClaim';
            }
          }
        } catch {}
      }

      try {
        if (!id || typeRaw === undefined || typeRaw === null) {
          // No reliable type; cannot proceed. Throttle logs below.
          if (!id || typeRaw === undefined || typeRaw === null) {
            if (!warnedIds.has(String(id))) {
              warnedIds.add(String(id));
              malformed++;
              if (malformed <= 1) {
                console.warn('[matrix-lite] skipping malformed outgoing request', req);
                if (!debugLoggedProto) {
                  debugLoggedProto = true;
                  try {
                    const proto = Object.getPrototypeOf(req);
                    const names = proto ? Object.getOwnPropertyNames(proto) : [];
                    console.log('[matrix-lite] outgoing request proto methods', names);
                  } catch {}
                }
              }
            }
            continue;
          }
        }

        let response: any | undefined;
        const typeStr = typeof typeRaw === 'string' ? typeRaw : undefined;
        const typeNum = typeof typeRaw === 'number' ? typeRaw : undefined;
        if (typeStr === 'KeysUpload' || typeNum === RequestType?.KeysUpload || typeVal === RequestType?.KeysUpload) {
          response = await keysUpload(homeserverUrl, accessToken, body ?? {});
        } else if (typeStr === 'KeysQuery' || typeNum === RequestType?.KeysQuery || typeVal === RequestType?.KeysQuery) {
          response = await keysQuery(homeserverUrl, accessToken, body ?? {});
        } else if (typeStr === 'KeysClaim' || typeNum === RequestType?.KeysClaim || typeVal === RequestType?.KeysClaim) {
          response = await keysClaim(homeserverUrl, accessToken, body ?? {});
        } else if (typeStr === 'ToDevice' || typeNum === RequestType?.ToDevice || typeVal === RequestType?.ToDevice) {
          // ToDeviceRequest exposes event_type and txn_id on the request, with body being JSON string for { messages }
          const eventType: string | undefined = getField(req, ['event_type', 'eventType', 'type']) || body?.event_type || body?.eventType || body?.type;
          const messages: Record<string, Record<string, any>> | undefined = body?.messages || getField(req, ['messages']);
          try {
            const userCount = Object.keys(messages || {}).length;
            const deviceCount = Object.values(messages || {}).reduce((acc: number, m: any) => acc + (m ? Object.keys(m).length : 0), 0);
            const sampleUsers = Object.keys(messages || {}).slice(0, 3);
            console.log('[matrix-lite][debug] drain ToDevice', { eventType, userCount, deviceCount, sampleUsers });
          } catch {}
          if (!eventType || !messages) {
            throw new Error('Malformed ToDevice request: missing event_type/messages');
          }
          response = await sendToDevice(homeserverUrl, accessToken, eventType, messages);
        } else if (typeStr === 'SignatureUpload' || typeNum === RequestType?.SignatureUpload || typeVal === RequestType?.SignatureUpload) {
          response = await uploadSignatures(homeserverUrl, accessToken, body ?? {});
        } else {
          // Not handled in this phase; log for visibility
          console.log('[matrix-lite] unhandled crypto request type:', typeRaw);
          // Best-effort: skip marking as sent so the engine can retry later
          continue;
        }

        try {
          // @ts-ignore - method name and signature depend on wasm bindings
          await (machine as any).markRequestAsSent(
            id,
            (typeVal as any) ?? (typeStr ?? typeNum),
            JSON.stringify(response ?? {})
          );
          completed++;
        } catch (err) {
          console.warn('[matrix-lite] markRequestAsSent failed', { id, type: typeRaw }, err);
        }
      } catch (err) {
        console.warn('[matrix-lite] crypto request failed', { id, type: typeRaw }, err);
        // Intentionally do not mark as sent on failure; engine will retry later
      }
    }
    // Avoid tight infinite loop if nothing could be processed
    if (completed === 0) {
      if (malformed > 1) {
        console.warn(`[matrix-lite] ${malformed} outgoing requests missing id/type; will retry later`);
      }
      return;
    }
  }
  } finally {
    draining = false;
  }
}

export async function importRoomKeys(keys: any[]): Promise<void> {
  if (!machine) return;
  try {
    const json = JSON.stringify(keys);
    const progress = (p: any) => {
      try {
        console.log('[matrix-lite] import progress', p?.progress ?? p);
      } catch {}
    };
    const m: any = machine as any;
    if (typeof m.importExportedRoomKeys === 'function') {
      await m.importExportedRoomKeys(json, progress);
    } else if (typeof m.importRoomKeys === 'function') {
      await m.importRoomKeys(json, progress);
    } else {
      console.warn('[matrix-lite] no import*RoomKeys function on OlmMachine');
    }
  } catch (err) {
    console.warn('[matrix-lite] importRoomKeys failed', err);
  }
}

export async function decryptEvent(ev: any, roomId: string): Promise<any | null> {
  if (!machine) return null;
  try {
    console.log('[matrix-lite][debug] decryptEvent', { roomId, type: ev?.type, event_id: ev?.event_id });
    const json = JSON.stringify(ev);
    const ds = new DecryptionSettings(TrustRequirement.Untrusted);
    // @ts-ignore wasm types
    const dec: any = await (machine as any).decryptRoomEvent(
      json,
      new RoomId(roomId),
      ds
    );
    const result = JSON.parse(dec.event);
    try {
      dec.free?.();
    } catch {}
    try {
      ds.free?.();
    } catch {}
    return result;
  } catch (err) {
    console.warn('[matrix-lite] decryptEvent failed', err);
    return null;
  }
}

/**
 * Encrypt an event for a room using the crypto engine.
 * Returns an object with type 'm.room.encrypted' and encrypted content on success, else null.
 */
export async function encryptEvent(
  roomId: string,
  eventType: string,
  content: any
): Promise<{ type: string; content: any } | null> {
  if (!machine) return null;
  try {
    console.log('[matrix-lite][debug] encryptEvent start', { roomId, eventType });
    // Ensure an outbound Megolm session exists and is shared
    await ensureOutboundMegolm(roomId);
    // Attempt common wasm binding shapes defensively
    const m: any = machine as any;
    // Prefer JSON string input if required by binding
    const json = JSON.stringify(content);
    let enc: any | undefined;
    // 1) encryptRoomEvent(RoomId, type, contentJson)
    try {
      if (typeof m.encryptRoomEvent === 'function') {
        enc = await m.encryptRoomEvent(new RoomId(roomId), eventType, json);
      }
    } catch {}
    // 2) encryptRoomEvent(roomIdStr, type, contentJson)
    if (!enc) {
      try {
        enc = await m.encryptRoomEvent(roomId, eventType, json);
      } catch {}
    }
    // 3) encrypt(roomIdStr, type, contentJson)
    if (!enc) {
      try {
        enc = await m.encrypt(roomId, eventType, json);
      } catch {}
    }
    if (!enc) return null;

    // Normalize output to { type, content }
    let type: string | undefined;
    let contentOut: any | undefined;
    try {
      type = enc.type || enc.event_type || 'm.room.encrypted';
    } catch {}
    try {
      const c = enc.content || enc.event || enc;
      contentOut = typeof c === 'string' ? JSON.parse(c) : c;
    } catch {
      contentOut = enc.content ?? enc;
    }
    // Drain any outgoing requests generated by encryption (e.g., key share)
    try {
      await drainOutgoingRequests();
    } catch {}
    if (!type || !contentOut) return null;
    console.log('[matrix-lite][debug] encryptEvent done', { type });
    return { type, content: contentOut };
  } catch (err) {
    console.warn('[matrix-lite] encryptEvent failed', err);
    return null;
  }
}

/**
 * Ensure an outbound Megolm session exists and is shared with room members.
 * Follows: updateTrackedUsers -> getMissingSessions -> keysClaim -> shareRoomKey.
 */
async function ensureOutboundMegolm(roomId: string): Promise<void> {
  if (!machine) return;
  const session = loadSession();
  if (!session) return;
  await withRoomShareLock(roomId, async () => {
  try {
    console.log('[matrix-lite][debug] ensureOutboundMegolm begin', { roomId });
    const members = await getRoomMembers(session.homeserverUrl, session.accessToken, roomId);
    const userIds = members.map((m) => m.userId);
    console.log('[matrix-lite][debug] ensureOutboundMegolm members', { count: userIds.length });
    if (userIds.length === 0) return;

    // Configure room settings to align with m.room.encryption
    try {
      const enc = await getRoomEncryptionState(session.homeserverUrl, session.accessToken, roomId);
      const rs = new RoomSettings();
      if (enc?.algorithm === 'm.megolm.v1.aes-sha2') {
        rs.algorithm = EncryptionAlgorithm.MegolmV1AesSha2;
      }
      // Allow unverified devices (bridges) unless explicitly configured otherwise
      try { (rs as any).onlyAllowTrustedDevices = false; } catch {}
      if (typeof enc?.rotation_period_ms === 'number') rs.sessionRotationPeriodMs = enc.rotation_period_ms;
      if (typeof enc?.rotation_period_msgs === 'number') rs.sessionRotationPeriodMessages = enc.rotation_period_msgs;
      // @ts-ignore wasm types
      await (machine as any).setRoomSettings(new RoomId(roomId), rs);
    } catch {}

    // Track users so device list is up-to-date
    try {
      const users = userIds.map((u) => new UserId(u));
      // @ts-ignore wasm types
      await (machine as any).updateTrackedUsers(users);
    } catch {}

    // Process any resulting key queries and refresh device lists for targets
    await drainOutgoingRequests();
    try {
      // Force-refresh device info akin to SDK; this can create KeysQuery requests
      for (const u of userIds) {
        try { await (machine as any).getUserDevices(new UserId(u)); } catch {}
      }
      await drainOutgoingRequests();
    } catch {}

    // Ensure Olm sessions via getMissingSessions -> KeysClaim
    let claimReq: any | undefined;
    try {
      const users = userIds.map((u) => new UserId(u));
      // @ts-ignore wasm types
      claimReq = await (machine as any).getMissingSessions(users);
    } catch {}
    if (claimReq) {
      try {
        const id: string = claimReq.id ?? claimReq.requestId ?? claimReq.request_id;
        let body: any = claimReq.body ?? claimReq.request ?? {};
        if (typeof body === 'string') {
          try { body = JSON.parse(body); } catch {}
        }
        try {
          const otk = body?.one_time_keys || {};
          const users = Object.keys(otk);
          const deviceTotal = Object.values(otk).reduce((acc: number, devs: any) => acc + (devs ? Object.keys(devs).length : 0), 0);
          console.log('[matrix-lite][debug] claim missing sessions', { users: users.length, deviceTotal });
        } catch {}
        const resp = await keysClaim(session.homeserverUrl, session.accessToken, body);
        try {
          // @ts-ignore wasm types
          await (machine as any).markRequestAsSent(id, RequestType.KeysClaim, JSON.stringify(resp ?? {}));
        } catch {}
      } catch (e) {
        console.warn('[matrix-lite] claim missing sessions failed', e);
      }
    }

    // Share room key with members
    try {
      const settings = new EncryptionSettings();
      try { settings.algorithm = EncryptionAlgorithm.MegolmV1AesSha2; } catch {}
      try { settings.sharingStrategy = CollectStrategy.allDevices(); } catch {}
      // History visibility used when creating sessions
      try {
        const hv = await getRoomHistoryVisibility(session.homeserverUrl, session.accessToken, roomId);
        if (hv === 'world_readable') settings.historyVisibility = HistoryVisibility.WorldReadable;
        else if (hv === 'shared') settings.historyVisibility = HistoryVisibility.Shared;
        else if (hv === 'invited') settings.historyVisibility = HistoryVisibility.Invited;
        else if (hv === 'joined') settings.historyVisibility = HistoryVisibility.Joined;
      } catch {}
      const freshUsers = () => userIds.map((u) => new UserId(u));
      // @ts-ignore wasm types
      let reqs: any[] = await (machine as any).shareRoomKey(new RoomId(roomId), freshUsers(), settings);
      if (Array.isArray(reqs) && reqs.length) {
        console.log('[matrix-lite][debug] shareRoomKey requests', { count: reqs.length });
        for (const r of reqs) {
          try {
            const id: string = r.id ?? r.requestId ?? r.request_id;
            let body: any = r.body ?? r.request ?? {};
            if (typeof body === 'string') {
              try { body = JSON.parse(body); } catch {}
            }
            const eventType: string | undefined = (r as any).event_type || (r as any).eventType || body?.event_type || body?.eventType || body?.type;
            const messages: Record<string, Record<string, any>> | undefined = body?.messages || (r as any).messages;
            if (!eventType || !messages) continue;
            try {
              const userCount = Object.keys(messages || {}).length;
              const deviceCount = Object.values(messages || {}).reduce((acc: number, m: any) => acc + (m ? Object.keys(m).length : 0), 0);
              const sampleUsers = Object.keys(messages || {}).slice(0, 3);
              console.log('[matrix-lite][debug] shareRoomKey to-device', { eventType, userCount, deviceCount, sampleUsers });
              try { lastShareByRoom.set(roomId, { eventType: String(eventType), userCount, deviceCount, sampleUsers, ts: Date.now() }); } catch {}
            } catch {}
            const resp = await sendToDevice(
              session.homeserverUrl,
              session.accessToken,
              eventType,
              messages
            );
            try {
              // @ts-ignore wasm types
              await (machine as any).markRequestAsSent(id, RequestType.ToDevice, JSON.stringify(resp ?? {}));
            } catch {}
          } catch (e) {
            console.warn('[matrix-lite] shareRoomKey to-device failed', e);
          }
        }
      } else {
        console.log('[matrix-lite][debug] shareRoomKey produced no requests');
        // Force rotate and retry once so newly-appeared devices (e.g., bridge) get a fresh session pre-send
        try {
          await (machine as any).invalidateGroupSession(new RoomId(roomId));
          // Recreate UserId objects: shareRoomKey invalidates them per wasm docs
          reqs = await (machine as any).shareRoomKey(new RoomId(roomId), freshUsers(), settings);
          if (Array.isArray(reqs) && reqs.length) {
            console.log('[matrix-lite][debug] shareRoomKey after rotate', { count: reqs.length });
            for (const r of reqs) {
              try {
                const id: string = r.id ?? r.requestId ?? r.request_id;
                let body: any = r.body ?? r.request ?? {};
                if (typeof body === 'string') {
                  try { body = JSON.parse(body); } catch {}
                }
                const eventType: string | undefined = (r as any).event_type || (r as any).eventType || body?.event_type || body?.eventType || body?.type;
                const messages: Record<string, Record<string, any>> | undefined = body?.messages || (r as any).messages;
                if (!eventType || !messages) continue;
                try {
                  const userCount = Object.keys(messages || {}).length;
                  const deviceCount = Object.values(messages || {}).reduce((acc: number, m: any) => acc + (m ? Object.keys(m).length : 0), 0);
                  const sampleUsers = Object.keys(messages || {}).slice(0, 3);
                  console.log('[matrix-lite][debug] shareRoomKey to-device (rotated)', { eventType, userCount, deviceCount, sampleUsers });
                  try { lastShareByRoom.set(roomId, { eventType: String(eventType), userCount, deviceCount, sampleUsers, rotated: true, ts: Date.now() }); } catch {}
                } catch {}
                const resp = await sendToDevice(
                  session.homeserverUrl,
                  session.accessToken,
                  eventType,
                  messages
                );
                try {
                  // @ts-ignore wasm types
                  await (machine as any).markRequestAsSent(id, RequestType.ToDevice, JSON.stringify(resp ?? {}));
                } catch {}
              } catch (e) {
                console.warn('[matrix-lite] shareRoomKey to-device (rotated) failed', e);
              }
            }
          }
        } catch (e) {
          console.warn('[matrix-lite] invalidate/share after no-requests failed', e);
        }
      }
    } catch {}
  } catch (err) {
    console.warn('[matrix-lite] ensureOutboundMegolm failed', err);
  }
  // After attempting to prepare, drain any resulting requests
  try { await drainOutgoingRequests(); } catch {}
}
  );
}

/**
 * When device lists change for some users, reshare the Megolm session to their devices in encrypted rooms.
 * Mirrors SDK behavior by checking joined encrypted rooms and ensuring outbound sessions.
 */
async function processDeviceListChanges(changedUserIds: string[]): Promise<void> {
  const session = loadSession();
  if (!session) return;
  console.log('[matrix-lite][debug] processDeviceListChanges', { changedUsers: changedUserIds.length });
  // Fetch joined rooms
  let rooms: string[] = [];
  try {
    rooms = await joinedRooms(session.homeserverUrl, session.accessToken);
  } catch {}
  if (!rooms || rooms.length === 0) return;
  console.log('[matrix-lite][debug] processDeviceListChanges rooms', { rooms: rooms.length });

  // Helper to limit concurrency
  const limit = Math.min(4, rooms.length);
  let idx = 0;
  const worker = async () => {
    while (true) {
      const i = idx++;
      if (i >= rooms.length) break;
      const roomId = rooms[i];
      try {
        const enc = await getRoomEncryptionState(session.homeserverUrl, session.accessToken, roomId);
        if (!enc) continue; // not encrypted
        const members = await getRoomMembers(session.homeserverUrl, session.accessToken, roomId);
        const memberSet = new Set(members.map((m) => m.userId));
        const intersects = changedUserIds.some((u) => memberSet.has(u));
        if (!intersects) continue;
        console.log('[matrix-lite][debug] reshare due to device change', { roomId });
        await ensureOutboundMegolm(roomId);
      } catch (e) {
        // best-effort: keep going
      }
    }
  };
  await Promise.all(new Array(limit).fill(0).map(() => worker()));
}

/** Force-rotate the outbound Megolm session for a room and re-share keys to members. */
export async function rotateMegolm(roomId: string): Promise<void> {
  if (!machine) return;
  try {
    // @ts-ignore wasm types
    await (machine as any).invalidateGroupSession(new RoomId(roomId));
  } catch (e) {
    console.warn('[matrix-lite] invalidateGroupSession failed', e);
  }
  try {
    await ensureOutboundMegolm(roomId);
    await drainOutgoingRequests();
  } catch (e) {
    console.warn('[matrix-lite] rotateMegolm ensure/share failed', e);
  }
}
