import * as matrixSdk from 'matrix-js-sdk';
import type { CryptoCallbacks } from 'matrix-js-sdk/lib/crypto-api';
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

  async createFromSession(
    session: MatrixSessionData,
    cryptoCallbacks?: CryptoCallbacks | Record<string, unknown>
  ) {
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
      cryptoCallbacks: cryptoCallbacks as CryptoCallbacks | undefined,
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

  async stop() {
    if (!this.client || !this.started) return;
    await this.client.stopClient();
    this.started = false;
  }

  async waitForPrepared(): Promise<void> {
    const c: any = this.client;
    if (!c) return;
    const state = c.getSyncState?.();
    if (state === 'PREPARED') return;

    await new Promise<void>((resolve) => {
      const onSync = (s: string) => {
        if (s === 'PREPARED') {
          c.removeListener(ClientEvent.Sync, onSync);
          resolve();
        }
      };
      c.on(ClientEvent.Sync, onSync);
    });
  }
}
