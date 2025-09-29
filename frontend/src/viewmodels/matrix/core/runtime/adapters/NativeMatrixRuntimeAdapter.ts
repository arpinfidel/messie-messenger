import type {
  MatrixRuntimeAdapter,
  MatrixRuntimeInitParams,
  MatrixRuntimeStartOpts,
  MatrixClientFacade,
  MatrixCryptoFacade,
  MatrixSecretStorageFacade,
} from '../MatrixRuntimeTypes';
import type { MatrixSessionData } from '../../MatrixSessionStore';
import { matrixNative } from '@/plugins/matrixNative';
import type { SyncState } from 'matrix-js-sdk';

export class NativeMatrixRuntimeAdapter implements MatrixRuntimeAdapter {
  readonly flavor = 'native';

  private session: MatrixSessionData | null = null;
  private homeserverOnly: string | null = null;
  private started = false;
  private readonly clientFacade = new NativeMatrixClientFacade(
    () => this.session,
    () => this.started
  );

  async init(params: MatrixRuntimeInitParams): Promise<void> {
    if (params.session) {
      this.session = params.session;
      this.homeserverOnly = null;
      await matrixNative.initFromSession({ session: params.session });
    } else if (params.homeserverUrl) {
      this.session = null;
      this.homeserverOnly = params.homeserverUrl;
      await matrixNative.initForHomeserver({ homeserverUrl: params.homeserverUrl });
    } else {
      throw new Error('Native runtime requires a session or homeserverUrl');
    }
    this.started = false;
    this.clientFacade.setStarted(false);
  }

  async start(_opts?: MatrixRuntimeStartOpts): Promise<void> {
    await matrixNative.start();
    this.started = true;
    this.clientFacade.setStarted(true);
  }

  async stop(): Promise<void> {
    if (!this.started) return;
    await matrixNative.stop();
    this.started = false;
    this.clientFacade.setStarted(false);
  }

  async dispose(): Promise<void> {
    if (this.started) {
      await matrixNative.stop().catch(() => undefined);
    }
    this.started = false;
    this.session = null;
    this.homeserverOnly = null;
    this.clientFacade.setStarted(false);
  }

  getClient(): MatrixClientFacade | null {
    return this.clientFacade;
  }

  getCrypto(): MatrixCryptoFacade | null {
    return null;
  }
}

class NativeMatrixClientFacade implements MatrixClientFacade {
  private started = false;

  constructor(
    private readonly getSession: () => MatrixSessionData | null,
    private readonly isStarted: () => boolean
  ) {}

  setStarted(value: boolean): void {
    this.started = value;
  }

  asMatrixClient(): undefined {
    return undefined;
  }

  isLoggedIn(): boolean {
    return !!this.getSession();
  }

  getUserId(): string | undefined {
    return this.getSession()?.userId;
  }

  getDeviceId(): string | undefined {
    return this.getSession()?.deviceId;
  }

  getAccessToken(): string | null {
    return this.getSession()?.accessToken ?? null;
  }

  async startClient(): Promise<void> {
    if (this.isStarted()) return;
    await matrixNative.start();
    this.started = true;
  }

  async stopClient(): Promise<void> {
    if (!this.isStarted()) return;
    await matrixNative.stop();
    this.started = false;
  }

  isInitialSyncComplete(): boolean {
    return this.started;
  }

  on(): void {
    throw new Error('Native runtime event streams are not implemented yet');
  }

  removeListener(): void {
    // No-op: event streams not wired yet.
  }

  async waitForSync(state: SyncState): Promise<void> {
    if (state !== 'PREPARED') return;
    if (this.started) return;
    const status = await matrixNative.currentState();
    if (!status.started) {
      throw new Error('Native runtime not started');
    }
  }

  async encryptAttachment(): Promise<{ data: ArrayBuffer; file: unknown }> {
    throw new Error('Native runtime attachment encryption not implemented');
  }

  async decryptEventIfNeeded(): Promise<void> {
    throw new Error('Native runtime decryption bridge not implemented');
  }

  async sendEvent(): Promise<string> {
    throw new Error('Native runtime sendEvent not implemented');
  }

  async uploadContent(): Promise<{ content_uri: string }> {
    throw new Error('Native runtime uploadContent not implemented');
  }

  isRoomEncrypted(): boolean {
    return this.getSession() !== null;
  }

  mxcUrlToHttp(
    mxcUrl: string,
    width?: number,
    height?: number,
    resizeMethod?: string,
    _allowDirectLinks?: boolean
  ): string | null {
    const s = this.getSession();
    if (!s || !mxcUrl || !mxcUrl.startsWith('mxc://')) return null;
    try {
      const base = s.homeserverUrl.replace(/\/$/, '');
      const withoutScheme = mxcUrl.slice('mxc://'.length);
      const slash = withoutScheme.indexOf('/');
      if (slash <= 0) return null;
      const server = withoutScheme.slice(0, slash);
      const mediaId = withoutScheme.slice(slash + 1);
      if (width && height) {
        const params = new URLSearchParams();
        params.set('width', String(width));
        params.set('height', String(height));
        if (resizeMethod) params.set('method', resizeMethod);
        return `${base}/_matrix/media/v3/thumbnail/${encodeURIComponent(server)}/${encodeURIComponent(mediaId)}?${params.toString()}`;
      }
      return `${base}/_matrix/media/v3/download/${encodeURIComponent(server)}/${encodeURIComponent(mediaId)}`;
    } catch {
      return null;
    }
  }

  getCrypto(): MatrixCryptoFacade | null {
    return null;
  }

  getSecretStorage(): MatrixSecretStorageFacade | null {
    return null;
  }
}
