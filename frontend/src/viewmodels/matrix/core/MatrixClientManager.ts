import * as matrixSdk from 'matrix-js-sdk';
import { decodeRecoveryKey, type CryptoCallbacks } from 'matrix-js-sdk/lib/crypto-api';
import type { MatrixSessionData } from './MatrixSessionStore';
import { ClientEvent } from 'matrix-js-sdk';

export type ClientGetter = () => matrixSdk.MatrixClient | null;

export class MatrixClientManager {
  private client: matrixSdk.MatrixClient | null = null;
  private started = false;

  getClient(): matrixSdk.MatrixClient | null {
    return this.client;
  }

  isStarted(): boolean {
    return this.started;
  }

  async createFromSession(session: MatrixSessionData, getRecoveryKey?: () => string | null) {
    const store = new matrixSdk.IndexedDBStore({
      indexedDB: window.indexedDB,
      dbName: 'matrix-js-sdk',
    });
    await store.startup();
    const opts: matrixSdk.ICreateClientOpts = {
      baseUrl: session.homeserverUrl,
      accessToken: session.accessToken,
      userId: session.userId,
      deviceId: session.deviceId,
      cryptoCallbacks: {
        getSecretStorageKey: async ({ keys }: { keys: Record<string, any> }) => {
          if (!getRecoveryKey || !getRecoveryKey()) return null;
          const keyId = Object.keys(keys)[0];
          if (!keyId) return null;
          const decoded = await decodeRecoveryKey(getRecoveryKey()!.trim());
          return [keyId, decoded];
        },
      },
      store,
    };

    this.client = matrixSdk.createClient(opts);
  }

  createForHomeserver(homeserverUrl: string) {
    this.client = matrixSdk.createClient({ baseUrl: homeserverUrl });
  }

  async initCryptoIfNeeded() {
    if (!this.client) return;
    // rust crypto init is idempotent/safe
    await this.client.initRustCrypto();
  }

  async start(opts?: matrixSdk.IStartClientOpts) {
    if (!this.client || this.started) return;
    await this.client.startClient(opts);
    this.started = true;
  }

  async kickSyncLoop(): Promise<void> {
    const client = this.client as any;
    if (!client?.syncApi) return;
    try {
      if (typeof client.syncApi.retryImmediately === 'function') {
        client.syncApi.retryImmediately();
      }
    } catch (err) {
      console.warn('[MatrixClientManager] kickSyncLoop failed', err);
    }
  }

  async stop() {
    if (!this.client || !this.started) return;
    await this.client.stopClient();
    this.started = false;
  }

  async waitForPrepared(): Promise<void> {
    const c = this.client;
    if (!c) return;
    const label = '[MatrixClientManager] waitForPrepared';
    console.time(label);
    if (c.isInitialSyncComplete()) {
      console.timeEnd(label);
      return;
    }

    await new Promise<void>((resolve) => {
      console.time('[MatrixClientManager] waitForPrepared -> listener duration');
      const onSync = (s: matrixSdk.SyncState) => {
        if (s === 'PREPARED') {
          c.removeListener(ClientEvent.Sync, onSync);
          console.timeEnd('[MatrixClientManager] waitForPrepared -> listener duration');
          resolve();
        }
      };
      c.on(ClientEvent.Sync, onSync);
    });
    console.timeEnd(label);
  }
}
