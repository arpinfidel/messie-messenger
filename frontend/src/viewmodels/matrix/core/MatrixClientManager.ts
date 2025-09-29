import * as matrixSdk from 'matrix-js-sdk';
import type { SyncState } from 'matrix-js-sdk/lib/matrix';
import { Capacitor } from '@capacitor/core';
import type { MatrixSessionData } from './MatrixSessionStore';
import {
  JsMatrixRuntimeAdapter,
  NativeMatrixRuntimeAdapter,
  type MatrixClientFacade,
  type MatrixRuntimeAdapter,
  type MatrixRuntimeFlavor,
  type MatrixRuntimeInitParams,
} from './runtime';

export type ClientGetter = () => matrixSdk.MatrixClient | null;

export class MatrixClientManager {
  private jsAdapter: JsMatrixRuntimeAdapter = new JsMatrixRuntimeAdapter();
  private nativeAdapter: NativeMatrixRuntimeAdapter = new NativeMatrixRuntimeAdapter();
  private runtime: MatrixRuntimeAdapter = this.jsAdapter;
  private runtimeFlavor: MatrixRuntimeFlavor = 'js';
  private clientFacade: MatrixClientFacade | null = null;
  private client: matrixSdk.MatrixClient | null = null;
  private started = false;
  private lastInitParams: MatrixRuntimeInitParams | null = null;

  getClient(): matrixSdk.MatrixClient | null {
    return this.client;
  }

  getClientFacade(): MatrixClientFacade | null {
    return this.clientFacade;
  }

  getRuntimeFlavor(): MatrixRuntimeFlavor {
    return this.runtimeFlavor;
  }

  isStarted(): boolean {
    return this.started;
  }

  async createFromSession(session: MatrixSessionData, getRecoveryKey?: () => string | null) {
    const params: MatrixRuntimeInitParams = { session, getRecoveryKey };
    this.lastInitParams = params;
    await this.activateRuntime(params);
  }

  async createForHomeserver(homeserverUrl: string) {
    const params: MatrixRuntimeInitParams = { homeserverUrl };
    this.lastInitParams = params;
    await this.activateRuntime(params);
  }

  async initCryptoIfNeeded() {
    if (this.runtimeFlavor !== 'js') return;
    const jsClient = this.clientFacade?.asMatrixClient?.();
    if (!jsClient) return;
    if (typeof jsClient.initRustCrypto === 'function') {
      await jsClient.initRustCrypto();
    }
  }

  async start(opts?: matrixSdk.IStartClientOpts) {
    if (this.started) return;
    try {
      await this.runtime.start({ client: opts });
      this.started = true;
      return;
    } catch (error) {
      if (this.runtimeFlavor === 'native' && this.isSlidingSyncUnavailable(error)) {
        console.warn('[MatrixClientManager] Native runtime missing sliding sync support, falling back to JS.');
        const fallback = this.lastInitParams;
        if (!fallback) {
          throw error;
        }
        await this.switchTo('js', fallback);
        await this.runtime.start({ client: opts });
        this.started = true;
        return;
      }
      throw error;
    }
  }

  async stop() {
    if (!this.started) return;
    await this.runtime.stop();
    this.started = false;
  }

  async waitForPrepared(): Promise<void> {
    if (!this.clientFacade) return;
    try {
      await this.clientFacade.waitForSync('PREPARED');
      return;
    } catch (err) {
      const jsClient = this.clientFacade.asMatrixClient?.();
      if (!jsClient) throw err;
      await waitForPreparedViaClient(jsClient);
    }
  }

  private async activateRuntime(params: MatrixRuntimeInitParams): Promise<void> {
    const flavor = this.chooseRuntimeFlavor();
    console.info('[MatrixClientManager] selecting runtime', flavor, params.session ? 'session' : 'homeserver');
    await this.switchTo(flavor, params);
  }

  private async switchTo(flavor: MatrixRuntimeFlavor, params: MatrixRuntimeInitParams): Promise<void> {
    if (this.runtime) {
      await this.runtime.dispose().catch(() => undefined);
    }
    const adapter = flavor === 'native' ? this.nativeAdapter : this.jsAdapter;
    try {
      await adapter.init(params);
      this.runtime = adapter;
      this.runtimeFlavor = flavor;
    } catch (err) {
      if (flavor === 'native') {
        console.error('[MatrixClientManager] Native runtime init failed; falling back to JS.', err);
        await this.jsAdapter.init(params);
        this.runtime = this.jsAdapter;
        this.runtimeFlavor = 'js';
      } else {
        throw err;
      }
    }
    this.clientFacade = this.runtime.getClient();
    this.client = this.clientFacade?.asMatrixClient?.() ?? null;
    this.started = false;
    console.info('[MatrixClientManager] active runtime', this.runtimeFlavor);
  }

  private chooseRuntimeFlavor(): MatrixRuntimeFlavor {
    if (this.nativeRuntimeEnabled()) return 'native';
    return 'js';
  }

  private nativeRuntimeEnabled(): boolean {
    const flag = getNativeFeatureFlag();
    if (!flag) {
      console.info('[MatrixClientManager] native runtime disabled via flag');
      return false;
    }
    try {
      if (typeof window === 'undefined') return false;
      const platform = Capacitor.getPlatform?.();
      if (platform === 'android') {
        console.info('[MatrixClientManager] native runtime enabled on Android platform');
        return true;
      }

      const available = Capacitor.isPluginAvailable?.('MatrixNative');
      if (available) return true;

      const pluginInstance = (Capacitor as any)?.Plugins?.MatrixNative;
      return !!pluginInstance;
    } catch (err) {
      console.warn('[MatrixClientManager] Native runtime detection failed', err);
      return false;
    }
  }

  private isSlidingSyncUnavailable(error: unknown): boolean {
    if (!error) return false;
    const message = (error as Error).message ?? '';
    if (message.includes('SlidingSyncUnavailableFallback')) return true;
    if (message.includes('Sliding sync version is missing')) return true;
    return false;
  }
}

function getNativeFeatureFlag(): boolean {
  const globalOverride = (globalThis as any)?.MESSIE_FORCE_NATIVE_MATRIX;
  if (typeof globalOverride === 'boolean') {
    console.info('[MatrixClientManager] native runtime flag override', globalOverride);
    return globalOverride;
  }
  const envValue = (import.meta as any)?.env?.VITE_MATRIX_NATIVE_ANDROID;
  if (typeof envValue === 'string') {
    return envValue === '1' || envValue.toLowerCase() === 'true';
  }
  try {
    return Capacitor.getPlatform?.() === 'android';
  } catch {
    return false;
  }
}

async function waitForPreparedViaClient(client: matrixSdk.MatrixClient): Promise<void> {
  if (client.isInitialSyncComplete()) return;
  await new Promise<void>((resolve) => {
    const onSync = (state: SyncState) => {
      if (state === 'PREPARED') {
        client.removeListener(matrixSdk.ClientEvent.Sync, onSync);
        resolve();
      }
    };
    client.on(matrixSdk.ClientEvent.Sync, onSync);
  });
}
