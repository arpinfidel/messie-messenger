import type { PluginListenerHandle } from '@capacitor/core';
import { matrixNative, type MatrixNativeVerificationEvent } from '@/plugins/matrixNative';
import { sasVerificationStore } from './SasVerificationStore';

let listenerPromise: Promise<PluginListenerHandle> | null = null;
let listenerHandle: PluginListenerHandle | null = null;

export async function ensureNativeVerificationBridge(): Promise<void> {
  if (listenerHandle) return;
  if (!listenerPromise) {
    listenerPromise = matrixNative.addListener('verificationEvent', handleVerificationEvent).then((handle) => {
      listenerHandle = handle;
      return handle;
    });
  }
  await listenerPromise;
}

function handleVerificationEvent(event: MatrixNativeVerificationEvent) {
  if (event.type === 'sas') {
    const emoji = event.emoji ?? [];
    sasVerificationStore.set({
      emoji,
      waiting: false,
      confirm: async () => {
        try {
          await matrixNative.confirmVerification();
          sasVerificationStore.update((current) => (current ? { ...current, waiting: true } : current));
        } catch (error) {
          console.error('[MatrixNative] Failed to confirm verification', error);
          sasVerificationStore.set(null);
        }
      },
      cancel: () => {
        void matrixNative.cancelVerification().catch((error) => {
          console.error('[MatrixNative] Failed to cancel verification', error);
        });
        sasVerificationStore.set(null);
      },
    });
    return;
  }

  if (event.type === 'state') {
    switch (event.phase) {
      case 'waiting_for_peer':
        sasVerificationStore.update((current) => (current ? { ...current, waiting: true } : current));
        break;
      case 'cancelled':
      case 'failed':
      case 'completed':
        sasVerificationStore.set(null);
        break;
      default:
        // ignored
        break;
    }
  }
}
