import {
  type CryptoCallbacks,
  type Verifier,
  VerifierEvent,
  VerificationPhase,
  VerificationRequestEvent,
  type VerificationRequest,
  type ShowSasCallbacks,
} from 'matrix-js-sdk/lib/crypto-api';
import { decodeRecoveryKey } from 'matrix-js-sdk/lib/crypto-api/recovery-key';
import type { IModuleViewModel } from '../../shared/IModuleViewModel';
import * as matrixSdk from 'matrix-js-sdk';
import { MatrixEvent } from 'matrix-js-sdk';
import { matrixSettings } from '../MatrixSettings';
import { VerificationMethod } from 'matrix-js-sdk/lib/types';
import { logger } from 'matrix-js-sdk/lib/logger.js';
import { sasVerificationStore } from './SasVerificationStore';

/* =========================
 * MatrixCryptoManager
 * ========================= */
export class MatrixCryptoManager {
  constructor(
    private readonly ctx: {
      getClient: () => matrixSdk.MatrixClient | null;
    }
  ) {}

  private get client() {
    return this.ctx.getClient();
  }

  async ensureVerificationAndKeys(): Promise<void> {
    if (!this.client) return;
    const crypto = this.client.getCrypto();
    if (!crypto) {
      console.warn('Crypto not available; skipping ensureVerificationAndKeys');
      return;
    }

    const { hasSSSS } = await this.hasSecretStorageAndBackup();
    try {
      if (hasSSSS || matrixSettings.recoveryKey?.trim()) {
        await crypto.checkKeyBackupAndEnable();
        console.log('Key backup checked/enabled (or already ok).');
      } else {
        console.log('[Backup] Skipping check/enable: no SSSS and no recovery key.');
      }
    } catch (e) {
      console.warn('Key backup enable/check failed (likely no SSSS / UIA required):', e);
    }

    const userId = this.client.getUserId();
    const deviceId = this.client.getDeviceId();
    if (!userId || !deviceId) return;

    try {
      const status = await crypto.getDeviceVerificationStatus(userId, deviceId);
      if (!status?.signedByOwner) {
        console.warn('Device is unverified — prompting/initiating verification is recommended.');
      }
    } catch (e) {
      console.warn('Failed to get device verification status:', e);
    }
  }

  // Decryption retries are handled opportunistically by the data layer and
  // event binder. No timeline iteration or scrollback here.

  async setupEncryptionSession(): Promise<void> {
    if (!this.client) return;
    const client = this.client;

    console.log('Setting up encryption session…');
    const crypto = client.getCrypto();
    if (!crypto) {
      console.warn('Crypto not available. Skipping setupEncryptionSession.');
      return;
    }

    try {
      console.log('Secret storage bootstrapped or already present (skipped if no user guidance).');
    } catch (error) {
      console.warn('bootstrapSecretStorage failed (may require UIA or already set):', error);
    }

    try {
      await crypto.bootstrapCrossSigning({
        authUploadDeviceSigningKeys: async (makeRequest) => {
          await makeRequest({});
        },
      });
      console.log('Cross-signing bootstrapped or already present.');
    } catch (error) {
      console.warn('bootstrapCrossSigning failed (likely UIA required or already present):', error);
    }

    try {
      await crypto.checkKeyBackupAndEnable();
      console.log('Key backup checked/enabled.');
    } catch (error) {
      console.warn('checkKeyBackupAndEnable failed:', error);
    }
  }

  async restoreFromRecoveryKey(): Promise<void> {
    if (!this.client) return;
    const crypto = this.client.getCrypto();
    if (!crypto) throw new Error('Crypto is not initialised on this client');

    const { hasSSSS, hasBackupSecret } = await this.hasSecretStorageAndBackup();

    if (!hasSSSS && !matrixSettings.recoveryKey?.trim()) {
      console.log('[Backup] No SSSS and no recovery key → skipping restore.');
      return;
    }
    if (hasSSSS && !hasBackupSecret && !matrixSettings.recoveryKey?.trim()) {
      console.log('[Backup] SSSS exists but no m.megolm_backup.v1 secret → skipping restore.');
      return;
    }

    const check = await crypto.checkKeyBackupAndEnable().catch(() => null);
    if (!check) {
      console.log('[Backup] No server backup or cannot enable → skipping restore.');
      return;
    }

    const info = await crypto.getKeyBackupInfo();
    if (!info?.version) {
      console.log('[Backup] Server backup lacks version → skipping restore.');
      return;
    }

    if (hasSSSS && hasBackupSecret) {
      await crypto.loadSessionBackupPrivateKeyFromSecretStorage();
    } else if (matrixSettings.recoveryKey?.trim()) {
      const priv = await decodeRecoveryKey(matrixSettings.recoveryKey.trim());
      await crypto.storeSessionBackupPrivateKey(priv, info.version);
    }

    const res = await crypto.restoreKeyBackup({
      progressCallback: (p) => console.log('[Backup] restore:', p.stage),
    });
    console.log('[Backup] Restore result:', res);
  }

  async debugSecrets(): Promise<void> {
    try {
      interface SecretStorage {
        getDefaultKeyId?: () => Promise<string | null>;
        has?: (name: string) => Promise<boolean>;
      }
      const ss = (this.client as unknown as { secretStorage?: SecretStorage }).secretStorage;
      if (!ss) {
        console.log('[SSSS] secretStorage undefined');
        return;
      }
      const defaultKey = await ss.getDefaultKeyId?.();
      console.log('[SSSS] default key id =', defaultKey);
      const hasBackupSecret = await ss.has?.('m.megolm_backup.v1');
      console.log('[SSSS] has m.megolm_backup.v1 =', hasBackupSecret);
    } catch (e) {
      console.warn('[SSSS] debug failed:', e);
    }
  }

  private async hasSecretStorageAndBackup(): Promise<{
    hasSSSS: boolean;
    hasBackupSecret: boolean;
  }> {
    interface SecretStorage {
      getDefaultKeyId?: () => Promise<string | null>;
      has?: (name: string) => Promise<boolean>;
    }
    const ss = (this.client as unknown as { secretStorage?: SecretStorage })?.secretStorage;
    if (!ss) return { hasSSSS: false, hasBackupSecret: false };
    const defaultKey = await ss.getDefaultKeyId?.();
    const hasSSSS = !!defaultKey;
    const hasBackupSecret = !!(await ss.has?.('m.megolm_backup.v1'));
    return { hasSSSS, hasBackupSecret };
  }

  async verifyCurrentDevice(): Promise<void> {
    if (!this.client) {
      console.error('Cannot verify device: Matrix client not initialized.');
      return;
    }
    const crypto = this.client.getCrypto();
    if (!crypto) {
      console.error('Crypto not available; cannot verify device.');
      return;
    }

    const PhaseName: Record<number, string> = {
      [VerificationPhase.Unsent]: 'Unsent',
      [VerificationPhase.Requested]: 'Requested',
      [VerificationPhase.Ready]: 'Ready',
      [VerificationPhase.Started]: 'Started',
      [VerificationPhase.Cancelled]: 'Cancelled',
      [VerificationPhase.Done]: 'Done',
    };

    const waitForVerifier = (vreq: VerificationRequest, ms = 8000): Promise<Verifier> =>
      new Promise((resolve, reject) => {
        if (vreq.verifier) return resolve(vreq.verifier);
        let settled = false;
        const onChange = () => {
          if (settled) return;
          if (vreq.verifier) {
            settled = true;
            vreq.off(VerificationRequestEvent.Change, onChange);
            resolve(vreq.verifier);
          }
        };
        vreq.on(VerificationRequestEvent.Change, onChange);
        setTimeout(() => {
          if (settled) return;
          settled = true;
          vreq.off(VerificationRequestEvent.Change, onChange);
          reject(new Error('verifier not provided in time'));
        }, ms);
      });

    const attachAndRunVerifier = (v: Verifier) => {
      v.on(VerifierEvent.ShowSas, async (sas: ShowSasCallbacks) => {
        console.log('[SAS] Emoji:', sas.sas.emoji);
        console.log('[SAS] Decimal:', sas.sas.decimal);
        sasVerificationStore.set({
          emoji: sas.sas.emoji || [],
          waiting: false,
          confirm: async () => {
            try {
              await sas.confirm();
              console.log('[SAS] Confirmed on this device. Waiting for peer…');
              sasVerificationStore.update((curr) =>
                curr ? { ...curr, waiting: true } : curr,
              );
            } catch (e) {
              console.error('[SAS] confirm() failed:', e);
              try {
                sas.cancel();
              } catch {}
              sasVerificationStore.set(null);
            }
          },
          cancel: () => {
            try {
              sas.mismatch();
            } catch {
              try {
                sas.cancel();
              } catch {}
            }
            sasVerificationStore.set(null);
          },
        });
      });
      v.on(VerifierEvent.Cancel, () => {
        sasVerificationStore.set(null);
      });
      v
        .verify()
        .then(() => {
          sasVerificationStore.set(null);
        })
        .catch((e) => {
          console.error('[Verification] verifier.verify() error:', e);
          sasVerificationStore.set(null);
        });
    };

    console.log('[Verification] Bootstrapping secret storage (if not already).');
    console.log('[Verification] Requesting own user verification.');
    const vreq = await crypto.requestOwnUserVerification();

    let startedMethod = false;

    const waitForDone = new Promise<void>((resolve, reject) => {
      const onChange = async () => {
        const phase = vreq.phase;
        console.log('[Verification] Phase:', PhaseName[phase], phase);

        if (phase === VerificationPhase.Requested) {
          console.log('[Verification] We initiated; waiting for peer to accept.');
          return;
        }

        if (
          (phase === VerificationPhase.Ready || phase === VerificationPhase.Started) &&
          !startedMethod
        ) {
          startedMethod = true;
          if (!vreq.verifier) {
            try {
              console.log('[Verification] No verifier yet → starting SAS.');
              const v = await vreq.startVerification(VerificationMethod.Sas);
              attachAndRunVerifier(v);
              return;
            } catch (e) {
              console.warn('[Verification] startVerification() failed (peer may have started):', e);
            }
          }
          try {
            const v = vreq.verifier ?? (await waitForVerifier(vreq, 8000));
            console.log('[Verification] Verifier available; attaching handlers.');
            attachAndRunVerifier(v);
          } catch (e) {
            console.error('[Verification] Still no verifier after wait:', e);
          }
          return;
        }

        if (phase === VerificationPhase.Done) {
          console.log('[Verification] Completed ✅');
          vreq.off(VerificationRequestEvent.Change, onChange);
          resolve();

          // No scrollback or bulk timeline decryption here; background
          // decryption updates propagate via event listeners.
          return;
        }
        if (phase === VerificationPhase.Cancelled) {
          const reason = vreq.cancellationCode || 'unknown';
          console.error('[Verification] Cancelled:', reason);
          vreq.off(VerificationRequestEvent.Change, onChange);
          reject(new Error(`Verification cancelled: ${reason}`));
        }
      };

      vreq.on(VerificationRequestEvent.Change, onChange);
    });

    try {
      vreq.emit(VerificationRequestEvent.Change);
    } catch {}

    const TIMEOUT_MS = 2 * 60 * 1000;
    const withTimeout = new Promise<void>((resolve, reject) => {
      const t = setTimeout(() => reject(new Error('Verification timed out')), TIMEOUT_MS);
      waitForDone.then(
        () => {
          clearTimeout(t);
          resolve();
        },
        (e) => {
          clearTimeout(t);
          reject(e);
        }
      );
    });

    try {
      console.log('[Verification] Waiting for completion…');
      await withTimeout;
      console.log('[Verification] Own user verification finished.');
    } catch (err) {
      console.error('[Verification] Failed:', err);
      try {
        await vreq.cancel();
      } catch {}
    }
  }
}
