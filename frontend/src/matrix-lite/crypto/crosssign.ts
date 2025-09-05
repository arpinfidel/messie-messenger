import * as nacl from 'tweetnacl';
import { canonicalize } from './canonical';
import {
  getDefaultSecretStorageKey,
  getSecret,
  getDefaultSecretStorageKeyFromAccountData,
  getSecretFromAccountData,
} from '../api/secret_storage';
import { uploadSignatures, uploadDeviceSigningKeys } from '../api/signatures';
import { keysQuery } from '../api/keys';
import { decodeRecoveryKey } from './backup';
import { decryptSSSSSecretAESHMAC } from './ssss';
import { getOlmMachine } from './engine';
import { DeviceId, RequestType, UserId } from '@matrix-org/matrix-sdk-crypto-wasm';

function bytesToBase64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64.replace(/\s+/g, ''));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function loadSelfSigningSeed(
  homeserverUrl: string,
  accessToken: string,
  userId: string,
  ssssKey: Uint8Array
): Promise<Uint8Array> {
  // Fetch default SSSS key id to resolve key metadata if needed (with fallbacks)
  let def = await getDefaultSecretStorageKey(homeserverUrl, accessToken).catch(() => null);
  if (!def) {
    def = await getDefaultSecretStorageKeyFromAccountData(
      homeserverUrl,
      accessToken,
      userId
    ).catch(() => null);
  }
  // Fetch and decrypt the self-signing secret (fallback to account_data variant)
  let enc = await getSecret(homeserverUrl, accessToken, 'm.cross_signing.self_signing').catch(
    () => null
  );
  if (!enc) {
    enc = await getSecretFromAccountData(
      homeserverUrl,
      accessToken,
      userId,
      'm.cross_signing.self_signing'
    ).catch(() => null);
  }
  const entry = (enc as any)?.encrypted;
  let dec: Uint8Array | null = null;
  if (entry && typeof entry === 'object') {
    const entryByKey = entry as Record<string, any>;
    const keyId = (def && (def as any).key) || Object.keys(entryByKey)[0];
    const data = keyId ? entryByKey[keyId] : Object.values(entryByKey)[0];
    dec = await decryptSSSSSecretAESHMAC(data, ssssKey, 'm.cross_signing.self_signing');
  }
  if (!dec) throw new Error('Failed to decrypt self-signing secret');
  // The payload is typically a base64 seed string
  try {
    const txt = new TextDecoder().decode(dec).trim();
    // Payload might be raw base64, or JSON with a `seed` property; handle both
    let seedB64 = txt;
    if (txt.startsWith('{')) {
      const o = JSON.parse(txt);
      seedB64 = String(o?.seed || o?.private || o?.sk || '');
    }
    const seed = base64ToBytes(seedB64);
    if (seed.length !== 32) throw new Error('Invalid seed length');
    return seed;
  } catch {
    if (dec.length !== 32) throw new Error('Self-signing seed not 32 bytes');
    return dec;
  }
}

async function decryptSSSSSecretAsString(
  homeserverUrl: string,
  accessToken: string,
  userId: string,
  ssssKey: Uint8Array,
  name: string
): Promise<string | null> {
  let def = await getDefaultSecretStorageKey(homeserverUrl, accessToken).catch(() => null);
  if (!def) {
    def = await getDefaultSecretStorageKeyFromAccountData(homeserverUrl, accessToken, userId).catch(
      () => null
    );
  }
  let enc = await getSecret(homeserverUrl, accessToken, name).catch(() => null);
  if (!enc) {
    enc = await getSecretFromAccountData(homeserverUrl, accessToken, userId, name).catch(() => null);
  }
  const entry = (enc as any)?.encrypted;
  if (entry && typeof entry === 'object') {
    const entryByKey = entry as Record<string, any>;
    const keyId = (def && (def as any).key) || Object.keys(entryByKey)[0];
    const data = keyId ? entryByKey[keyId] : Object.values(entryByKey)[0];
    const dec = await decryptSSSSSecretAESHMAC(data, ssssKey, name);
    if (!dec) return null;
    try {
      return new TextDecoder().decode(dec);
    } catch {
      return null;
    }
  }
  return null;
}

function stripForSigning(obj: any): any {
  if (!obj || typeof obj !== 'object') return obj;
  const cpy: any = Array.isArray(obj) ? [] : {};
  for (const [k, v] of Object.entries(obj)) {
    if (k === 'signatures' || k === 'unsigned') continue;
    cpy[k] = typeof v === 'object' && v ? stripForSigning(v) : v;
  }
  return cpy;
}

export async function verifyOwnDeviceWithRecoveryKey(
  homeserverUrl: string,
  accessToken: string,
  userId: string,
  deviceId: string
): Promise<void> {
  const recKey = (window as any)?.matrixSettings?.recoveryKey || '';
  // Fallback to a globally stored setting via local import if available
  let recoveryKey: string = typeof recKey === 'string' ? recKey : '';
  if (!recoveryKey) {
    // Dynamic import to avoid circular deps
    try {
      const mod = await import('../../viewmodels/matrix/MatrixSettings');
      recoveryKey = String((mod as any).matrixSettings?.recoveryKey || '');
    } catch {}
  }
  if (!recoveryKey?.trim()) throw new Error('Recovery key not set');

  const ssssKey = decodeRecoveryKey(recoveryKey.trim());

  // Attempt SDK-like flow first: import keys into the OlmMachine and ask it to verify()
  const machine = getOlmMachine();
  if (machine) {
    try {
      const msk = await decryptSSSSSecretAsString(
        homeserverUrl,
        accessToken,
        userId,
        ssssKey,
        'm.cross_signing.master'
      );
      const ssk = await decryptSSSSSecretAsString(
        homeserverUrl,
        accessToken,
        userId,
        ssssKey,
        'm.cross_signing.self_signing'
      );
      const usk = await decryptSSSSSecretAsString(
        homeserverUrl,
        accessToken,
        userId,
        ssssKey,
        'm.cross_signing.user_signing'
      );
      if (ssk || msk || usk) {
        // @ts-ignore wasm types may differ at build time
        const status = await (machine as any).importCrossSigningKeys(
          msk ?? null,
          ssk ?? null,
          usk ?? null
        );
        try {
          // @ts-ignore wasm types
          const dev = await (machine as any).getDevice(new UserId(userId), new DeviceId(deviceId));
          if (dev) {
            try {
              // @ts-ignore wasm types
              const req = await dev.verify();
              // Send the signature upload request and mark as sent
              const bodyRaw: any = (req as any).body ?? (req as any).json ?? (req as any).request;
              const body =
                typeof bodyRaw === 'string' && bodyRaw.length > 0 ? JSON.parse(bodyRaw) : bodyRaw || {};
              const resp = await uploadSignatures(homeserverUrl, accessToken, body);
              const id: string = (req as any).id;
              // @ts-ignore wasm types
              await (machine as any).markRequestAsSent(id, RequestType.SignatureUpload, JSON.stringify(resp ?? {}));
              console.log('[cross-signing] Uploaded signature for device via machine', deviceId);

              // Ensure public cross-signing keys are published if missing
              try {
                const q = await keysQuery(homeserverUrl, accessToken, { device_keys: { [userId]: [] } });
                const hasMaster = !!q?.master_keys?.[userId];
                if (!hasMaster) {
                  // @ts-ignore wasm types
                  const boots = await (machine as any).bootstrapCrossSigning(true);
                  try {
                    const sendReq = async (reqObj: any) => {
                      if (!reqObj) return;
                      const id2: string | undefined = (reqObj as any).id;
                      const bodyRaw2: any = (reqObj as any).body ?? (reqObj as any).json ?? (reqObj as any).request;
                      const body2 =
                        typeof bodyRaw2 === 'string' && bodyRaw2.length > 0
                          ? JSON.parse(bodyRaw2)
                          : bodyRaw2 || {};
                      const type2: any = (reqObj as any).type;
                      // Heuristics based on presence of fields
                      if (type2 === RequestType.KeysUpload) {
                        const resp2 = await (await import('../api/keys')).keysUpload(
                          homeserverUrl,
                          accessToken,
                          body2
                        );
                        await (machine as any).markRequestAsSent(
                          id2,
                          RequestType.KeysUpload,
                          JSON.stringify(resp2 ?? {})
                        );
                      } else if (type2 === RequestType.SignatureUpload) {
                        const resp2 = await uploadSignatures(homeserverUrl, accessToken, body2);
                        await (machine as any).markRequestAsSent(
                          id2,
                          RequestType.SignatureUpload,
                          JSON.stringify(resp2 ?? {})
                        );
                      } else {
                        // Non-outgoing UploadSigningKeysRequest: no id/type; send without marking
                        try {
                          await uploadDeviceSigningKeys(homeserverUrl, accessToken, body2);
                        } catch (e) {
                          console.warn('[cross-signing] uploadDeviceSigningKeys failed', e);
                        }
                      }
                    };
                    await sendReq((boots as any).uploadKeysRequest);
                    await sendReq((boots as any).uploadSigningKeysRequest);
                    await sendReq((boots as any).uploadSignaturesRequest);
                    console.log('[cross-signing] Published public cross-signing keys');
                  } catch (e) {
                    console.warn('[cross-signing] bootstrapCrossSigning requests failed', e);
                  }
                }
              } catch (e) {
                console.warn('[cross-signing] ensure public keys failed', e);
              }
              try {
                dev.free?.();
              } catch {}
              return; // done
            } finally {
              try {
                dev.free?.();
              } catch {}
            }
          }
        } catch (e) {
          console.warn('[cross-signing] device.verify() failed; falling back to manual signing', e);
        }
      }
    } catch (e) {
      console.warn('[cross-signing] importCrossSigningKeys failed; falling back to manual signing', e);
    }
  }

  // Fallback: manual device signature using self-signing key seed
  const seed = await loadSelfSigningSeed(homeserverUrl, accessToken, userId, ssssKey);
  const kp = nacl.sign.keyPair.fromSeed(seed);
  const ssPubB64 = bytesToBase64(kp.publicKey).replace(/=+$/g, '');
  const ssKeyId = `ed25519:${ssPubB64}`;

  // Fetch our current device keys from the server
  const query = await keysQuery(homeserverUrl, accessToken, {
    device_keys: { [userId]: [deviceId] },
    timeout: 10000,
  });
  const dev = query?.device_keys?.[userId]?.[deviceId];
  if (!dev) throw new Error('Device keys not found for signing');

  const toSign = stripForSigning(dev);
  const canon = canonicalize(toSign);
  const sig = nacl.sign.detached(new TextEncoder().encode(canon), kp.secretKey);
  const sigB64 = bytesToBase64(sig).replace(/=+$/g, '');
  const signedDev = { ...dev, signatures: { ...(dev.signatures || {}) } } as any;
  if (!signedDev.signatures[userId]) signedDev.signatures[userId] = {};
  signedDev.signatures[userId][ssKeyId] = sigB64;
  const body = { [userId]: { [deviceId]: signedDev } };
  await uploadSignatures(homeserverUrl, accessToken, body);
  console.log('[cross-signing] Uploaded signature for device', deviceId);
}
