import {
  initAsync,
  OlmMachine,
  UserId,
  DeviceId,
  DeviceLists,
  RoomId,
  DecryptionSettings,
  TrustRequirement,
  EncryptionSettings,
  EncryptionAlgorithm,
} from '@matrix-org/matrix-sdk-crypto-wasm';
import { loadSession } from '../runtime/session';
import { keysUpload, keysQuery, keysClaim } from '../api/keys';
import { RequestType } from '@matrix-org/matrix-sdk-crypto-wasm';
import { sendToDevice } from '../api/to_device';
import { uploadSignatures } from '../api/signatures';
import { getRoomMembers } from '../api/rooms';

let machine: OlmMachine | null = null;
let debugLoggedProto = false;
let draining = false;

export async function initCrypto(userId: string, deviceId: string): Promise<void> {
  if (machine) return;
  await initAsync();
  machine = await OlmMachine.initialize(new UserId(userId), new DeviceId(deviceId));
  console.log('[matrix-lite] crypto engine initialized');
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

export async function handleSync(data: any): Promise<any[]> {
  if (!machine || !data) return [];
  try {
    // Opportunistically respond to m.room_key_request by sharing keys to the requester
    try {
      const reqs: any[] = Array.isArray(data?.to_device?.events) ? data.to_device.events : [];
      for (const ev of reqs) {
        if (ev?.type === 'm.room_key_request' && ev?.content?.action === 'request') {
          try {
            await respondToRoomKeyRequest(ev);
          } catch (e) {
            console.warn('[matrix-lite] failed to respond to room_key_request', e);
          }
        }
      }
    } catch {}

    const toDevice = JSON.stringify(data.to_device?.events || []);
    const changed = (data.device_lists?.changed || []).map((u: string) => new UserId(u));
    const left = (data.device_lists?.left || []).map((u: string) => new UserId(u));
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
    return out;
  } catch (err) {
    console.warn('[matrix-lite] crypto sync error', err);
    return [];
  }
}

async function respondToRoomKeyRequest(ev: any): Promise<void> {
  if (!machine || !ev || !ev.content) return;
  const session = loadSession();
  if (!session) return;
  const { homeserverUrl, accessToken } = session;

  const sender: string | undefined = typeof ev.sender === 'string' ? ev.sender : undefined;
  const body = ev.content?.body || {};
  const roomId: string | undefined = typeof body?.room_id === 'string' ? body.room_id : undefined;
  if (!sender || !roomId) return;

  try {
    const user = new UserId(sender);
    // Track requester to ensure we have their devices
    try {
      // @ts-ignore wasm types
      await (machine as any).updateTrackedUsers([user.clone()]);
    } catch {}

    // Establish Olm sessions to requester devices if needed
    // @ts-ignore wasm types
    const claimReq: any = await (machine as any).getMissingSessions([user.clone()]);
    if (claimReq) {
      try {
        const bodyRaw: any = (claimReq as any).body;
        const claimBody =
          typeof bodyRaw === 'string' && bodyRaw.length > 0 ? JSON.parse(bodyRaw) : bodyRaw || {};
        const resp = await keysClaim(homeserverUrl, accessToken, claimBody);
        const id = (claimReq as any).id;
        // @ts-ignore wasm types
        await (machine as any).markRequestAsSent(id, RequestType.KeysClaim, JSON.stringify(resp ?? {}));
      } catch (e) {
        console.warn('[matrix-lite] key request: keysClaim failed', e);
      }
    }

    // Allow sharing to unverified devices for this room and requester
    const settings = new EncryptionSettings();
    settings.algorithm = EncryptionAlgorithm.MegolmV1AesSha2;
    try {
      (settings as any).onlyAllowTrustedDevices = false;
    } catch {}
    try {
      // @ts-ignore
      await (machine as any).setRoomSettings(new RoomId(roomId), settings);
    } catch {}

    // Generate share messages for just this requester
    // @ts-ignore wasm types
    const shareMessages: any[] = await (machine as any).shareRoomKey(new RoomId(roomId), [user], settings);
    if (Array.isArray(shareMessages)) {
      for (const req of shareMessages) {
        try {
          const id = (req as any).id;
          const evType = (req as any).event_type || (req as any).eventType;
          const txnId = (req as any).txn_id || (req as any).txnId || Date.now().toString();
          const bodyRaw: any = (req as any).body ?? (req as any).json ?? (req as any).request;
          const bodyObj =
            typeof bodyRaw === 'string' && bodyRaw.length > 0 ? JSON.parse(bodyRaw) : bodyRaw || {};
          const messages = bodyObj?.messages || bodyObj;
          const resp = await sendToDevice(homeserverUrl, accessToken, evType, txnId, messages);
          // @ts-ignore wasm types
          await (machine as any).markRequestAsSent(id, RequestType.ToDevice, JSON.stringify(resp ?? {}));
        } catch (e) {
          console.warn('[matrix-lite] key request: sendToDevice failed', e);
        }
      }
    }
    // Process any additional outgoing requests generated by sharing
    await drainOutgoingRequests();
  } catch (e) {
    console.warn('[matrix-lite] respondToRoomKeyRequest failed', e);
  }
}

/**
 * Drain and fulfill outgoing requests from the crypto engine.
 * Handles device key upload, query, and claim.
 */
async function drainOutgoingRequests(): Promise<void> {
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
        } else if (
          typeStr === 'SignatureUpload' ||
          typeNum === RequestType?.SignatureUpload ||
          typeVal === RequestType?.SignatureUpload
        ) {
          response = await uploadSignatures(homeserverUrl, accessToken, body ?? {});
        } else if (
          typeStr === 'ToDevice' ||
          typeNum === RequestType?.ToDevice ||
          typeVal === RequestType?.ToDevice
        ) {
          const eventType = body?.event_type || body?.eventType;
          const txnId = body?.txn_id || body?.txnId || Date.now().toString();
          const messages = body?.messages || {};
          response = await sendToDevice(
            homeserverUrl,
            accessToken,
            eventType,
            txnId,
            messages
          );
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
 * Encrypt an event for a given room. Automatically shares the
 * Megolm session with all joined members if needed.
 */
export async function encryptEvent(
  roomId: string,
  eventType: string,
  content: any
): Promise<any | null> {
  if (!machine) throw new Error('Crypto engine not initialized');
  const session = loadSession();
  if (!session) throw new Error('Not logged in');
  const { homeserverUrl, accessToken } = session;

  try {
    // Fetch joined members to determine key share targets
    const members = await getRoomMembers(homeserverUrl, accessToken, roomId);
    const users = members.map((m) => new UserId(m.userId));

    // Ensure the crypto machine tracks all recipient users so device lists are kept up to date
    try {
      // It's ok to call updateTrackedUsers repeatedly; the machine will de-dup
      // @ts-ignore wasm types
      await (machine as any).updateTrackedUsers(users.map((u) => u.clone()));
    } catch (e) {
      console.warn('[matrix-lite] updateTrackedUsers failed', e);
    }

    // Ensure we have Olm sessions with all target devices
    // `getMissingSessions` consumes the passed UserIds, so pass in clones
    // @ts-ignore wasm types
    const claimReq: any = await (machine as any).getMissingSessions(
      users.map((u) => u.clone())
    );
    if (claimReq) {
      try {
        const bodyRaw: any = (claimReq as any).body;
        const body =
          typeof bodyRaw === 'string' && bodyRaw.length > 0
            ? JSON.parse(bodyRaw)
            : bodyRaw || {};
        const resp = await keysClaim(homeserverUrl, accessToken, body);
        const id = (claimReq as any).id;
        // @ts-ignore wasm types
        await (machine as any).markRequestAsSent(
          id,
          RequestType.KeysClaim,
          JSON.stringify(resp ?? {})
        );
      } catch (err) {
        console.warn('[matrix-lite] keysClaim failed', err);
      }
    }

    // Process any follow-up requests from session establishment
    await drainOutgoingRequests();

    const settings = new EncryptionSettings();
    settings.algorithm = EncryptionAlgorithm.MegolmV1AesSha2;
    // Allow sharing to unverified devices so bridges/bots without cross-signing still receive keys
    try {
      (settings as any).onlyAllowTrustedDevices = false;
    } catch {}
    try {
      // Persist the room policy so future key requests from unverified devices are served
      // @ts-ignore wasm types
      await (machine as any).setRoomSettings(new RoomId(roomId), settings);
    } catch (e) {
      console.warn('[matrix-lite] setRoomSettings failed', e);
    }

    // @ts-ignore wasm types
    const shareMessages: any[] = await (machine as any).shareRoomKey(
      new RoomId(roomId),
      users,
      settings
    );

    if (Array.isArray(shareMessages)) {
      for (const req of shareMessages) {
        try {
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

          const id = getField(req, ['id', 'requestId', 'request_id']);
          const evType = getField(req, ['event_type', 'eventType']);
          const txnId = getField(req, ['txn_id', 'txnId']);
          const bodyRaw: any = getField(req, ['body', 'json', 'request']);
          const bodyObj =
            typeof bodyRaw === 'string' && bodyRaw.length > 0
              ? JSON.parse(bodyRaw)
              : bodyRaw || {};
          const messages = bodyObj?.messages || bodyObj;
          const resp = await sendToDevice(
            homeserverUrl,
            accessToken,
            evType,
            txnId,
            messages
          );
          try {
            // @ts-ignore wasm types
            await (machine as any).markRequestAsSent(
              id,
              RequestType.ToDevice,
              JSON.stringify(resp ?? {})
            );
          } catch (err) {
            console.warn('[matrix-lite] markRequestAsSent failed', err);
          }
        } catch (err) {
          console.warn('[matrix-lite] sendToDevice failed', err);
        }
      }
    }

    // Process any follow-up requests (e.g., key queries)
    await drainOutgoingRequests();

    const json = JSON.stringify(content);
    // @ts-ignore wasm types
    const enc = await (machine as any).encryptRoomEvent(
      new RoomId(roomId),
      eventType,
      json
    );
    return JSON.parse(enc);
  } catch (err) {
    console.warn('[matrix-lite] encryptEvent failed', err);
    return null;
  }
}
