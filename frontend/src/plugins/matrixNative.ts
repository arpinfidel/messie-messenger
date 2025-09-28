import { registerPlugin, type PluginListenerHandle } from '@capacitor/core';
import type { MatrixNativeCryptoBundle } from '@/types/matrixNative';

export interface MatrixNativeSessionPayload {
  homeserverUrl: string;
  userId: string;
  accessToken: string;
  deviceId?: string;
  refreshToken?: string;
}

export interface MatrixNativeState {
  started: boolean;
  hasSession: boolean;
  session?: {
    homeserverUrl: string;
    userId: string;
    deviceId?: string;
  };
  homeserverUrl?: string;
}

export interface MatrixNativeLoginResult {
  homeserverUrl: string;
  userId: string;
  accessToken: string;
  deviceId?: string;
  refreshToken?: string;
}

export type MatrixNativeVerificationEvent =
  | {
      type: 'state';
      phase:
        | 'requested'
        | 'accepted'
        | 'sas_started'
        | 'waiting_for_peer'
        | 'cancelled'
        | 'completed'
        | 'failed'
        | 'request_received';
      reason?: string;
    }
  | {
      type: 'sas';
      emoji: [string, string][];
      variant?: 'emoji' | 'decimal';
    };

export interface MatrixNativePlugin {
  initFromSession(payload: { session: MatrixNativeSessionPayload }): Promise<void>;
  initForHomeserver(payload: { homeserverUrl: string }): Promise<void>;
  start(): Promise<void>;
  stop(): Promise<void>;
  currentState(): Promise<MatrixNativeState>;
  importCryptoState(payload: { bundle: MatrixNativeCryptoBundle }): Promise<void>;
  exportCryptoState(): Promise<{ bundle?: MatrixNativeCryptoBundle }>;
  login(payload: { username: string; password: string; deviceName?: string }): Promise<MatrixNativeLoginResult>;
  verifyCurrentDevice(): Promise<void>;
  confirmVerification(): Promise<void>;
  cancelVerification(): Promise<void>;
  addListener(
    eventName: 'verificationEvent',
    listenerFunc: (event: MatrixNativeVerificationEvent) => void
  ): Promise<PluginListenerHandle>;
}

class MatrixNativeWeb implements MatrixNativePlugin {
  private state: MatrixNativeState = {
    started: false,
    hasSession: false,
  };
  private bundle?: MatrixNativeCryptoBundle;

  async initFromSession(payload: { session: MatrixNativeSessionPayload }): Promise<void> {
    this.state = {
      started: false,
      hasSession: true,
      session: {
        homeserverUrl: payload.session.homeserverUrl,
        userId: payload.session.userId,
        deviceId: payload.session.deviceId,
      },
    };
  }

  async initForHomeserver(payload: { homeserverUrl: string }): Promise<void> {
    this.state = {
      started: false,
      hasSession: false,
      homeserverUrl: payload.homeserverUrl,
    };
  }

  async start(): Promise<void> {
    this.state = { ...this.state, started: true };
  }

  async stop(): Promise<void> {
    this.state = { ...this.state, started: false };
  }

  async currentState(): Promise<MatrixNativeState> {
    return this.state;
  }

  async importCryptoState(payload: { bundle: MatrixNativeCryptoBundle }): Promise<void> {
    this.bundle = payload.bundle;
  }

  async exportCryptoState(): Promise<{ bundle?: MatrixNativeCryptoBundle }> {
    return { bundle: this.bundle };
  }

  async login(): Promise<MatrixNativeLoginResult> {
    throw new Error('Native Matrix login is not available in the web stub.');
  }

  async verifyCurrentDevice(): Promise<void> {
    console.warn('[MatrixNativeWeb] verifyCurrentDevice is not available in this environment.');
  }

  async confirmVerification(): Promise<void> {
    console.warn('[MatrixNativeWeb] confirmVerification is not available in this environment.');
  }

  async cancelVerification(): Promise<void> {
    console.warn('[MatrixNativeWeb] cancelVerification is not available in this environment.');
  }

  async addListener(): Promise<PluginListenerHandle> {
    return {
      remove: async () => {
        /* no-op */
      },
    };
  }
}

export const matrixNative = registerPlugin<MatrixNativePlugin>('MatrixNative', {
  web: () => new MatrixNativeWeb(),
});

if (typeof window !== 'undefined') {
  (window as any).__messieMatrixNative = matrixNative;
}
