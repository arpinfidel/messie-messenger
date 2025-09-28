import { registerPlugin } from '@capacitor/core';
import type { MatrixNativeCryptoBundle } from '@/types/matrixNative';

export interface MatrixNativeSessionPayload {
  homeserverUrl: string;
  userId: string;
  accessToken: string;
  deviceId?: string;
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

export interface MatrixNativePlugin {
  initFromSession(payload: { session: MatrixNativeSessionPayload }): Promise<void>;
  initForHomeserver(payload: { homeserverUrl: string }): Promise<void>;
  start(): Promise<void>;
  stop(): Promise<void>;
  currentState(): Promise<MatrixNativeState>;
  importCryptoState(payload: { bundle: MatrixNativeCryptoBundle }): Promise<void>;
  exportCryptoState(): Promise<{ bundle?: MatrixNativeCryptoBundle }>;
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
}

export const matrixNative = registerPlugin<MatrixNativePlugin>('MatrixNative', {
  web: () => new MatrixNativeWeb(),
});
