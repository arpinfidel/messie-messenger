import * as matrixSdk from 'matrix-js-sdk';
import type { MatrixClient } from 'matrix-js-sdk';
import { matrixNative } from '@/plugins/matrixNative';
import type { MatrixNativeCryptoBundle } from '@/types/matrixNative';

export async function exportJsCryptoBundle(client: MatrixClient): Promise<MatrixNativeCryptoBundle> {
  const crypto = client.getCrypto();
  if (!crypto) {
    throw new Error('Matrix crypto is not initialised; cannot export secrets.');
  }
  const bundle: MatrixNativeCryptoBundle = {
    userId: client.getUserId() ?? undefined,
    deviceId: client.getDeviceId() ?? undefined,
  };

  try {
    bundle.roomKeys = await crypto.exportRoomKeys();
  } catch (err) {
    console.warn('[cryptoTransfer] Failed to export room keys', err);
  }

  try {
    const info = await crypto.getKeyBackupInfo();
    bundle.backup = { ...(bundle.backup ?? {}), info };
  } catch (err) {
    console.warn('[cryptoTransfer] getKeyBackupInfo failed', err);
  }

  const secretStorage = (client as unknown as { secretStorage?: { getDefaultKeyId?: () => Promise<string | null> } })
    .secretStorage;
  if (secretStorage?.getDefaultKeyId) {
    try {
      bundle.secretStorageDefaultKeyId = await secretStorage.getDefaultKeyId();
    } catch (err) {
      console.warn('[cryptoTransfer] secretStorage.getDefaultKeyId failed', err);
    }
  }

  return bundle;
}

export async function pushBundleToNative(bundle: MatrixNativeCryptoBundle): Promise<void> {
  await matrixNative.importCryptoState({ bundle });
}

export async function pullBundleFromNative(): Promise<MatrixNativeCryptoBundle | null> {
  const res = await matrixNative.exportCryptoState();
  return res.bundle ?? null;
}
