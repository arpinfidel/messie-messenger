import { Capacitor } from '@capacitor/core';
import type { MatrixClient } from 'matrix-js-sdk';
import { NativeCrypto } from '@messie/native-crypto';

let cachedHandleId: string | null = null;
let initialisationAttempted = false;

export type NativeCryptoBootstrapResult = {
  enabled: boolean;
  handleId?: string;
};

/**
 * Try to initialise the native crypto backend. Returns false if we should fall back
 * to the stock matrix-js-sdk WASM implementation.
 */
export async function ensureNativeCrypto(client: MatrixClient): Promise<NativeCryptoBootstrapResult> {
  if (cachedHandleId) {
    return { enabled: true, handleId: cachedHandleId };
  }

  if (initialisationAttempted) {
    return { enabled: false };
  }
  initialisationAttempted = true;

  if (!Capacitor.isNativePlatform()) {
    return { enabled: false };
  }

  const userId = client.getUserId();
  const deviceId = client.getDeviceId();
  if (!userId || !deviceId) {
    console.warn('[NativeCrypto] Missing user or device id; falling back to wasm.');
    return { enabled: false };
  }

  try {
    const result = await NativeCrypto.init({
      userId,
      deviceId,
      homeserverUrl: client.getHomeserverUrl?.() ?? '',
      dataPath: 'messie-crypto',
    });
    cachedHandleId = result.handleId;
    console.info('[NativeCrypto] Native crypto initialised');
    return { enabled: true, handleId: cachedHandleId };
  } catch (err) {
    console.warn('[NativeCrypto] Failed to initialise native crypto; fallback to wasm', err);
    return { enabled: false };
  }
}

export function getNativeHandleId(): string | null {
  return cachedHandleId;
}
