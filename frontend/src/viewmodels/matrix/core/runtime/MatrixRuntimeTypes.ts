import type * as matrixSdk from 'matrix-js-sdk';
import type { MatrixClient, SyncState } from 'matrix-js-sdk';
import type { MatrixEvent } from 'matrix-js-sdk/lib/models/event';
import type { IStartClientOpts } from 'matrix-js-sdk/lib/client';
import type { IKeyBackupInfo } from 'matrix-js-sdk/lib/crypto-api';
import type {
  DeviceVerificationStatus,
  IBootstrapCrossSigningOpts,
  MatrixClientCrypto,
  RestoreKeyBackupResult,
  VerificationRequest,
} from 'matrix-js-sdk/lib/matrix';
import type { MatrixSessionData } from '../MatrixSessionStore';

export type MatrixRuntimeFlavor = 'js' | 'native';

export interface MatrixRuntimeDiscoveryContext {
  platform: 'web' | 'android' | 'ios' | 'desktop';
  nativeBridgeAvailable: boolean;
  featureFlagNative: boolean;
  forcedRuntime?: MatrixRuntimeFlavor;
}

export interface MatrixRuntimeSelection {
  flavor: MatrixRuntimeFlavor;
  reason: string;
  fallback?: MatrixRuntimeFlavor;
}

export interface MatrixRuntimeDiscovery {
  detect(context: MatrixRuntimeDiscoveryContext): Promise<MatrixRuntimeSelection>;
}

export interface MatrixRuntimeInitParams {
  session?: MatrixSessionData;
  homeserverUrl?: string;
  getRecoveryKey?: () => string | null;
  telemetry?: MatrixRuntimeTelemetry;
}

export interface MatrixRuntimeTelemetry {
  recordSelection(result: MatrixRuntimeSelection): void;
  recordError(payload: { stage: 'init' | 'start' | 'stop'; runtime: MatrixRuntimeFlavor; error: Error }): void;
}

export interface MatrixRuntimeAdapter {
  readonly flavor: MatrixRuntimeFlavor;
  init(params: MatrixRuntimeInitParams): Promise<void>;
  start(opts?: MatrixRuntimeStartOpts): Promise<void>;
  stop(): Promise<void>;
  dispose(): Promise<void>;
  getClient(): MatrixClientFacade | null;
  getCrypto(): MatrixCryptoFacade | null;
}

export interface MatrixRuntimeStartOpts {
  client?: IStartClientOpts;
  enablePush?: boolean;
}

export interface MatrixClientFacade {
  /** Returns the underlying Matrix client if available (JS runtime). */
  asMatrixClient?(): MatrixClient | undefined;

  isLoggedIn(): boolean;
  getUserId(): string | undefined;
  getDeviceId(): string | undefined;
  getAccessToken(): string | null;
  startClient(opts?: IStartClientOpts): Promise<void>;
  stopClient(): Promise<void>;
  isInitialSyncComplete(): boolean;
  on(event: string, listener: (...args: any[]) => void): void;
  removeListener(event: string, listener: (...args: any[]) => void): void;
  waitForSync(state: SyncState): Promise<void>;
  encryptAttachment?(blob: Blob): Promise<{ data: ArrayBuffer; file: unknown }>;
  decryptEventIfNeeded?(event: MatrixEvent): Promise<void>;
  sendEvent(roomId: string, eventType: string, content: Record<string, unknown>): Promise<string>;
  uploadContent(file: File | Blob, opts: { type?: string }): Promise<{ content_uri: string }>;
  isRoomEncrypted(roomId: string): boolean;
  mxcUrlToHttp(
    mxcUrl: string,
    width?: number,
    height?: number,
    resizeMethod?: string,
    allowDirectLinks?: boolean
  ): string | null;
  getCrypto(): MatrixCryptoFacade | null;
  getSecretStorage?(): MatrixSecretStorageFacade | null;
}

export interface MatrixCryptoFacade {
  readonly rawCrypto?: MatrixClientCrypto;
  checkKeyBackupAndEnable(): Promise<void>;
  getDeviceVerificationStatus(userId: string, deviceId: string): Promise<DeviceVerificationStatus | null>;
  bootstrapCrossSigning(options: IBootstrapCrossSigningOpts): Promise<void>;
  getKeyBackupInfo(): Promise<IKeyBackupInfo | null>;
  loadSessionBackupPrivateKeyFromSecretStorage(): Promise<void>;
  storeSessionBackupPrivateKey(privateKey: Uint8Array | ArrayBuffer | string, version: string): Promise<void>;
  restoreKeyBackup(opts: { progressCallback?: (progress: { stage: string }) => void }): Promise<RestoreKeyBackupResult | null>;
  requestOwnUserVerification(): Promise<VerificationRequest>;
}

export interface MatrixSecretStorageFacade {
  getDefaultKeyId(): Promise<string | null>;
  has(name: string): Promise<boolean>;
}

export interface MatrixRuntimeSelector {
  choose(context: MatrixRuntimeDiscoveryContext): Promise<MatrixRuntimeSelection>;
  getAdapter(flavor: MatrixRuntimeFlavor): MatrixRuntimeAdapter;
}
