import * as matrixSdk from 'matrix-js-sdk';
import { ClientEvent } from 'matrix-js-sdk';
import { decodeRecoveryKey } from 'matrix-js-sdk/lib/crypto-api/recovery-key';
import type {
  MatrixClient,
  MatrixClientCrypto,
  IBootstrapCrossSigningOpts,
  IKeyBackupInfo,
  RestoreKeyBackupResult,
  VerificationRequest,
} from 'matrix-js-sdk/lib/matrix';
import type { ICreateClientOpts } from 'matrix-js-sdk/lib/client';
import {
  type MatrixRuntimeAdapter,
  type MatrixRuntimeInitParams,
  type MatrixRuntimeStartOpts,
  type MatrixClientFacade,
  type MatrixCryptoFacade,
  type MatrixSecretStorageFacade,
} from '../MatrixRuntimeTypes';

type ClientSupplier = () => MatrixClient | null;

export class JsMatrixRuntimeAdapter implements MatrixRuntimeAdapter {
  readonly flavor = 'js';

  private client: MatrixClient | null = null;
  private started = false;
  private clientFacade: MatrixClientFacade | null = null;
  private cryptoFacade: MatrixCryptoFacade | null = null;

  async init(params: MatrixRuntimeInitParams): Promise<void> {
    if (this.client) {
      await this.dispose();
    }

    const opts = await this.buildClientOptions(params);
    this.client = matrixSdk.createClient(opts);
    this.clientFacade = new JsMatrixClientFacade(() => this.client);
    this.cryptoFacade = new JsMatrixCryptoFacade(() => this.client?.getCrypto() ?? null);
    this.started = false;
  }

  async start(opts?: MatrixRuntimeStartOpts): Promise<void> {
    if (!this.client || this.started) return;
    await this.client.startClient(opts?.client);
    this.started = true;
  }

  async stop(): Promise<void> {
    if (!this.client || !this.started) return;
    await this.client.stopClient();
    this.started = false;
  }

  async dispose(): Promise<void> {
    await this.stop().catch(() => undefined);
    try {
      await this.client?.store?.destroy?.();
    } catch (err) {
      console.warn('[JsMatrixRuntimeAdapter] store.destroy failed', err);
    }
    this.client = null;
    this.clientFacade = null;
    this.cryptoFacade = null;
  }

  getClient(): MatrixClientFacade | null {
    return this.clientFacade;
  }

  getCrypto(): MatrixCryptoFacade | null {
    return this.cryptoFacade;
  }

  private async buildClientOptions(params: MatrixRuntimeInitParams): Promise<ICreateClientOpts> {
    if (params.session) {
      const session = params.session;
      const store = await this.createStore();
      const cryptoCallbacks = params.getRecoveryKey
        ? {
            getSecretStorageKey: async ({ keys }: { keys: Record<string, unknown> }) => {
              const recover = params.getRecoveryKey?.();
              if (!recover) return null;
              const keyId = Object.keys(keys ?? {})[0];
              if (!keyId) return null;
              const decoded = await decodeRecoveryKey(recover.trim());
              return [keyId, decoded] as const;
            },
          }
        : undefined;

      return {
        baseUrl: session.homeserverUrl,
        accessToken: session.accessToken,
        userId: session.userId,
        deviceId: session.deviceId,
        cryptoCallbacks,
        store,
      } satisfies ICreateClientOpts;
    }

    if (params.homeserverUrl) {
      return { baseUrl: params.homeserverUrl } satisfies ICreateClientOpts;
    }

    throw new Error('Matrix runtime requires either a session or homeserverUrl.');
  }

  private async createStore(): Promise<matrixSdk.IndexedDBStore | matrixSdk.MemoryStore> {
    if (typeof indexedDB !== 'undefined') {
      const store = new matrixSdk.IndexedDBStore({ indexedDB, dbName: 'matrix-js-sdk' });
      await store.startup();
      return store;
    }

    const memoryStore = new matrixSdk.MemoryStore({ localStorage: undefined });
    memoryStore.startup();
    return memoryStore;
  }
}

class JsMatrixClientFacade implements MatrixClientFacade {
  constructor(private readonly getClient: ClientSupplier) {}

  asMatrixClient(): MatrixClient | undefined {
    return this.getClient() ?? undefined;
  }

  isLoggedIn(): boolean {
    return !!this.getClient()?.isLoggedIn();
  }

  getUserId(): string | undefined {
    return this.getClient()?.getUserId() ?? undefined;
  }

  getDeviceId(): string | undefined {
    return this.getClient()?.getDeviceId() ?? undefined;
  }

  getAccessToken(): string | null {
    return this.getClient()?.getAccessToken() ?? null;
  }

  async startClient(opts?: matrixSdk.IStartClientOpts): Promise<void> {
    const client = this.ensure();
    await client.startClient(opts);
  }

  async stopClient(): Promise<void> {
    const client = this.ensure();
    await client.stopClient();
  }

  isInitialSyncComplete(): boolean {
    return !!this.getClient()?.isInitialSyncComplete();
  }

  on(event: string, listener: (...args: any[]) => void): void {
    this.ensure().on(event as ClientEvent, listener);
  }

  removeListener(event: string, listener: (...args: any[]) => void): void {
    this.ensure().removeListener(event as ClientEvent, listener);
  }

  async waitForSync(state: matrixSdk.SyncState): Promise<void> {
    const client = this.ensure();
    if (client.getSyncState() === state) return;
    await new Promise<void>((resolve) => {
      const handler = (newState: matrixSdk.SyncState) => {
        if (newState === state) {
          client.removeListener(ClientEvent.Sync, handler);
          resolve();
        }
      };
      client.on(ClientEvent.Sync, handler);
    });
  }

  async encryptAttachment(blob: Blob): Promise<{ data: ArrayBuffer; file: unknown }> {
    const client = this.ensure();
    if (!client.encryptAttachment) {
      throw new Error('encryptAttachment not available on JS runtime client');
    }
    return client.encryptAttachment(blob);
  }

  async decryptEventIfNeeded(event: matrixSdk.MatrixEvent): Promise<void> {
    const client = this.ensure();
    if (client.decryptEventIfNeeded) {
      await client.decryptEventIfNeeded(event);
    }
  }

  async sendEvent(
    roomId: string,
    eventType: string,
    content: Record<string, unknown>
  ): Promise<string> {
    const client = this.ensure();
    const res = await client.sendEvent(roomId, eventType, content);
    return (res as { event_id?: string }).event_id ?? '';
  }

  uploadContent(file: File | Blob, opts: { type?: string }): Promise<{ content_uri: string }> {
    const client = this.ensure();
    return client.uploadContent(file, opts);
  }

  isRoomEncrypted(roomId: string): boolean {
    return !!this.getClient()?.isRoomEncrypted(roomId);
  }

  mxcUrlToHttp(
    mxcUrl: string,
    width?: number,
    height?: number,
    resizeMethod?: string,
    allowDirectLinks?: boolean
  ): string | null {
    return this.getClient()?.mxcUrlToHttp(mxcUrl, width, height, resizeMethod, allowDirectLinks) ?? null;
  }

  getCrypto(): MatrixCryptoFacade | null {
    const crypto = this.getClient()?.getCrypto() ?? null;
    return crypto ? new JsMatrixCryptoFacade(() => crypto) : null;
  }

  getSecretStorage(): MatrixSecretStorageFacade | null {
    const client = this.getClient();
    const ss = (client as any)?.secretStorage;
    if (!client || !ss) return null;
    return new JsMatrixSecretStorageFacade(ss);
  }

  private ensure(): MatrixClient {
    const client = this.getClient();
    if (!client) throw new Error('Matrix client not initialised');
    return client;
  }
}

class JsMatrixCryptoFacade implements MatrixCryptoFacade {
  constructor(private readonly getCrypto: () => MatrixClientCrypto | null) {}

  get rawCrypto(): MatrixClientCrypto | undefined {
    return this.getCrypto() ?? undefined;
  }

  private ensure(): MatrixClientCrypto {
    const crypto = this.getCrypto();
    if (!crypto) throw new Error('Matrix crypto not available');
    return crypto;
  }

  checkKeyBackupAndEnable(): Promise<void> {
    return this.ensure().checkKeyBackupAndEnable();
  }

  getDeviceVerificationStatus(userId: string, deviceId: string) {
    return this.ensure().getDeviceVerificationStatus(userId, deviceId);
  }

  bootstrapCrossSigning(options: IBootstrapCrossSigningOpts): Promise<void> {
    return this.ensure().bootstrapCrossSigning(options);
  }

  getKeyBackupInfo(): Promise<IKeyBackupInfo | null> {
    return this.ensure().getKeyBackupInfo();
  }

  loadSessionBackupPrivateKeyFromSecretStorage(): Promise<void> {
    return this.ensure().loadSessionBackupPrivateKeyFromSecretStorage();
  }

  storeSessionBackupPrivateKey(
    privateKey: Uint8Array | ArrayBuffer | string,
    version: string
  ): Promise<void> {
    return this.ensure().storeSessionBackupPrivateKey(privateKey as any, version);
  }

  restoreKeyBackup(
    opts: { progressCallback?: (progress: { stage: string }) => void }
  ): Promise<RestoreKeyBackupResult | null> {
    return this.ensure().restoreKeyBackup(opts as any);
  }

  requestOwnUserVerification(): Promise<VerificationRequest> {
    return this.ensure().requestOwnUserVerification();
  }
}

class JsMatrixSecretStorageFacade implements MatrixSecretStorageFacade {
  constructor(private readonly secretStorage: {
    getDefaultKeyId?: () => Promise<string | null>;
    has?: (name: string) => Promise<boolean>;
  }) {}

  getDefaultKeyId(): Promise<string | null> {
    return this.secretStorage.getDefaultKeyId?.() ?? Promise.resolve(null);
  }

  has(name: string): Promise<boolean> {
    return this.secretStorage.has?.(name) ?? Promise.resolve(false);
  }
}
