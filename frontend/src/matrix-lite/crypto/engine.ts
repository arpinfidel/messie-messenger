import {
  initAsync,
  OlmMachine,
  UserId,
  DeviceId,
  DeviceLists,
  RoomId,
  DecryptionSettings,
  TrustRequirement,
} from '@matrix-org/matrix-sdk-crypto-wasm';
import { loadSession } from '../runtime/session';
import { keysUpload, keysQuery, keysClaim } from '../api/keys';
import { RequestType } from '@matrix-org/matrix-sdk-crypto-wasm';

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
