function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesConcat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

async function hkdfSha256(rawKey: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) throw new Error('WebCrypto is not available');
  const ikm = await subtle.importKey('raw', rawKey, 'HKDF', false, ['deriveBits']);
  // SDK uses 8-byte zero salt for SSSS HKDF
  const zeroSalt = new Uint8Array(8);
  // @ts-ignore info supported
  const bits = await subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: zeroSalt, info }, ikm, length * 8);
  return new Uint8Array(bits);
}

export async function decryptSSSSSecretAESHMAC(
  entry: any,
  ssssKey: Uint8Array,
  name: string
): Promise<Uint8Array | null> {
  try {
    const subtle = globalThis.crypto?.subtle;
    if (!subtle) throw new Error('WebCrypto is not available');
    const ivB64 = entry?.iv;
    const macB64 = entry?.mac;
    const ctB64 = entry?.ciphertext;
    if (typeof ivB64 !== 'string' || typeof macB64 !== 'string' || typeof ctB64 !== 'string') {
      return null;
    }
    const iv = base64ToBytes(ivB64);
    const ct = base64ToBytes(ctB64);
    const mac = base64ToBytes(macB64);

    // SDK derives with info = secret name; keep that first, but try a couple fallbacks for robustness
    const infos = [name, 'm.secret_storage.v1.aes-hmac-sha2', ''];
    for (const info of infos) {
      try {
        const derived = await hkdfSha256(ssssKey, new TextEncoder().encode(info), 64);
        const aesKeyBytes = derived.slice(0, 32);
        const hmacKeyBytes = derived.slice(32);
        const hmacKey = await subtle.importKey(
          'raw',
          hmacKeyBytes,
          { name: 'HMAC', hash: 'SHA-256' },
          false,
          ['verify']
        );
        // SDK verifies MAC over ciphertext only
        let verified = await subtle.verify('HMAC', hmacKey, mac, ct);
        if (!verified) {
          // Older implementations may have used IV||ciphertext
          const ivPlusCt = bytesConcat(iv, ct);
          verified = await subtle.verify('HMAC', hmacKey, mac, ivPlusCt);
        }
        if (!verified) continue;
        const aesKey = await subtle.importKey('raw', aesKeyBytes, { name: 'AES-CTR' }, false, ['decrypt']);
        const decBuf = await subtle.decrypt({ name: 'AES-CTR', counter: iv, length: 64 }, aesKey, ct);
        return new Uint8Array(decBuf);
      } catch {}
    }
    return null;
    return null;
  } catch (e) {
    console.warn('[ssss] decrypt failed', e);
    return null;
  }
}
