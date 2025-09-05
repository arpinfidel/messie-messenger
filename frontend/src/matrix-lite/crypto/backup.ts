import bs58 from 'bs58';
import * as nacl from 'tweetnacl';
import { initAsync, BackupDecryptionKey } from '@matrix-org/matrix-sdk-crypto-wasm';

const OLM_RECOVERY_KEY_PREFIX = [0x8b, 0x01];
const KEY_SIZE = 32;

export function decodeRecoveryKey(recoveryKey: string): Uint8Array {
  const cleaned = recoveryKey.replace(/\s+/g, '');
  const decoded = bs58.decode(cleaned);
  // verify parity
  let parity = 0;
  for (const b of decoded) parity ^= b;
  if (parity !== 0) throw new Error('Incorrect parity in recovery key');
  // verify prefix
  for (let i = 0; i < OLM_RECOVERY_KEY_PREFIX.length; i++) {
    if (decoded[i] !== OLM_RECOVERY_KEY_PREFIX[i]) throw new Error('Incorrect prefix in recovery key');
  }
  if (decoded.length !== OLM_RECOVERY_KEY_PREFIX.length + KEY_SIZE + 1) {
    throw new Error('Incorrect length for recovery key');
  }
  return Uint8Array.from(
    decoded.slice(OLM_RECOVERY_KEY_PREFIX.length, OLM_RECOVERY_KEY_PREFIX.length + KEY_SIZE)
  );
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function utf8Decode(buf: ArrayBuffer | Uint8Array): string {
  const dec = new TextDecoder();
  return dec.decode(buf instanceof Uint8Array ? buf : new Uint8Array(buf));
}

async function hkdfSha256(rawKey: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) throw new Error('WebCrypto is not available');
  const ikm = await subtle.importKey('raw', rawKey, 'HKDF', false, ['deriveBits']);
  const bits = await subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info },
    ikm,
    length * 8
  );
  return new Uint8Array(bits);
}

export async function deriveBackupKey(rawKey: Uint8Array): Promise<Uint8Array> {
  // Many clients present the backup key directly (32 bytes). Keep identity here
  // and let decryptors apply HKDF as needed per algorithm.
  return new Uint8Array(rawKey);
}

export async function decryptBackupEntry(
  entry: any,
  keyBytes: Uint8Array,
  algorithm: string
): Promise<any | null> {
  try {
    const subtle = globalThis.crypto?.subtle;
    if (!subtle) throw new Error('WebCrypto is not available');
    const payload = entry?.session_data ? entry.session_data : entry;
    const cipher = payload?.ciphertext;
    const ivStr = payload?.iv;
    const mac = payload?.mac;
    if (typeof cipher !== 'string' || typeof ivStr !== 'string') return null;
    const iv = base64ToBytes(ivStr);
    const data = base64ToBytes(cipher);

    if (/curve25519/i.test(algorithm)) {
      return decryptBackupEntryCurve25519(entry, keyBytes);
    }

    if (/gcm/i.test(algorithm)) {
      const key = await subtle.importKey('raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt']);
      const decBuf = await subtle.decrypt({ name: 'AES-GCM', iv, tagLength: 128 }, key, data);
      return JSON.parse(utf8Decode(decBuf));
    } else {
      // AES-CTR; optionally verify HMAC if provided (aes-hmac-sha2)
      if (typeof mac === 'string' && mac.length > 0) {
        try {
          // Try HKDF to derive 64 bytes and split into AES + HMAC keys
          const derived = await hkdfSha256(keyBytes, new TextEncoder().encode('backup'), 64);
          const aesKeyBytes = derived.slice(0, 32);
          const hmacKeyBytes = derived.slice(32);
          const hmacKey = await subtle.importKey('raw', hmacKeyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
          const ok = await subtle.verify('HMAC', hmacKey, base64ToBytes(mac), new Uint8Array([...iv, ...data]));
          if (!ok) {
            // Try alternative info label used by some clients
            const alt = await hkdfSha256(keyBytes, new TextEncoder().encode('MEGOLM_BACKUP_V1'), 64);
            const altAes = alt.slice(0, 32);
            const altHmac = alt.slice(32);
            const altHmacKey = await subtle.importKey('raw', altHmac, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
            const okAlt = await subtle.verify('HMAC', altHmacKey, base64ToBytes(mac), new Uint8Array([...iv, ...data]));
            if (!okAlt) return null;
            const k = await subtle.importKey('raw', altAes, { name: 'AES-CTR' }, false, ['decrypt']);
            const decBuf = await subtle.decrypt({ name: 'AES-CTR', counter: iv, length: 64 }, k, data);
            return JSON.parse(utf8Decode(decBuf));
          }
          const k = await subtle.importKey('raw', aesKeyBytes, { name: 'AES-CTR' }, false, ['decrypt']);
          const decBuf = await subtle.decrypt({ name: 'AES-CTR', counter: iv, length: 64 }, k, data);
          return JSON.parse(utf8Decode(decBuf));
        } catch (e) {
          console.warn('[backup-restore] HMAC verify/decrypt failed', e);
          return null;
        }
      }
      // AES-CTR without HMAC present; try best-effort
      const key = await subtle.importKey('raw', keyBytes, { name: 'AES-CTR' }, false, ['decrypt']);
      try {
        const decBuf = await subtle.decrypt({ name: 'AES-CTR', counter: iv, length: 64 }, key, data);
        return JSON.parse(utf8Decode(decBuf));
      } catch {
        const decBuf = await subtle.decrypt({ name: 'AES-CTR', counter: iv, length: 128 }, key, data);
        return JSON.parse(utf8Decode(decBuf));
      }
    }
  } catch (err) {
    console.warn('[backup-restore] decrypt failed', err);
    return null;
  }
}

function tryParseJsonUtf8(bytes: Uint8Array): any | null {
  try {
    const txt = new TextDecoder().decode(bytes);
    return JSON.parse(txt);
  } catch {
    return null;
  }
}

function clampScalar(sk: Uint8Array): Uint8Array {
  // X25519 clamping
  const out = new Uint8Array(sk);
  out[0] &= 248;
  out[31] &= 127;
  out[31] |= 64;
  return out;
}

function bytesToBase64(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  // btoa requires binary string input
  return btoa(s);
}

function padB64(s: string): string {
  const t = s.replace(/\s+/g, '');
  const rem = t.length % 4;
  return rem === 0 ? t : t + '='.repeat(4 - rem);
}

async function decryptBackupEntryCurve25519(entry: any, keyBytes: Uint8Array): Promise<any | null> {
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) throw new Error('WebCrypto is not available');
  try {
    const payload = entry?.session_data ? entry.session_data : entry;
    const ephemeralB64 = payload?.ephemeral;
    const cipherB64 = payload?.ciphertext;
    const macB64 = payload?.mac;
    if (typeof ephemeralB64 !== 'string' || typeof cipherB64 !== 'string' || typeof macB64 !== 'string') {
      return null;
    }
    try {
      const eLen = ephemeralB64?.length ?? 0;
      const cLen = cipherB64?.length ?? 0;
      const mLen = macB64?.length ?? 0;
      console.log('[backup-restore] decryptV1 inputs lens', { eLen, cLen, mLen });
    } catch {}
    // Use the Rust WASM to perform the official v1 decryption
    await initAsync();
    // Accept either raw 32-byte key or base64-encoded UTF-8
    let b64key: string;
    if (keyBytes.length === 32) {
      b64key = bytesToBase64(keyBytes);
    } else {
      const asText = new TextDecoder().decode(keyBytes).trim();
      b64key = asText;
    }
    b64key = padB64(b64key);
    // @ts-ignore - types from wasm
    const decKey = (BackupDecryptionKey as any).fromBase64(b64key);
    try {
      // @ts-ignore - decryptV1 signature from wasm
      const json = decKey.decryptV1(padB64(ephemeralB64), padB64(macB64), padB64(cipherB64));
      return JSON.parse(json);
    } finally {
      try {
        // @ts-ignore - wasm free method may exist
        decKey.free?.();
      } catch {}
    }
  } catch (e) {
    const err = e as any;
    const msg = (err && (err.message || err.toString && err.toString())) || 'unknown';
    console.warn('[backup-restore] curve25519 decrypt failed', msg);
    return null;
  }
}
