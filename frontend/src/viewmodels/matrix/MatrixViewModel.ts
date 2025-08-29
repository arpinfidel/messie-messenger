import { type CryptoCallbacks } from 'matrix-js-sdk/lib/crypto-api';
import * as matrixSdk from 'matrix-js-sdk';
import { decodeRecoveryKey } from 'matrix-js-sdk/lib/crypto-api/recovery-key';
import { logger } from 'matrix-js-sdk/lib/logger.js';

import { writable, type Writable } from 'svelte/store';

import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import { type IMatrixTimelineItem } from '@/viewmodels/matrix/MatrixTimelineItem';
import { matrixSettings } from '@/viewmodels/matrix/MatrixSettings';
import { MatrixTimelineService } from '@/viewmodels/matrix/MatrixTimelineService';

import { MatrixSessionStore, type MatrixSessionData } from './core/MatrixSessionStore';
import { MatrixClientManager } from './core/MatrixClientManager';
import { OutgoingMessageQueue } from './core/OutgoingMessageQueue';
import { MatrixEventBinder } from './core/MatrixEventBinder';
import { MatrixCryptoManager } from './core/MatrixCryptoManager';
import { TimelineRepository } from './core/TimelineRepository';

export class MatrixViewModel implements IModuleViewModel {
  private static instance: MatrixViewModel;

  // lifecycle / state
  private hydrationState: 'idle' | 'syncing' | 'decrypting' | 'ready' = 'idle';

  // composition
  private sessionStore = new MatrixSessionStore();
  private clientMgr = new MatrixClientManager();
  private cryptoMgr = new MatrixCryptoManager({ getClient: () => this.clientMgr.getClient() });
  private timelineSvc = new MatrixTimelineService(
    {
      getClient: () => this.clientMgr.getClient(),
      isStarted: () => this.clientMgr.isStarted(),
      getHydrationState: () => this.hydrationState,
    },
    new TimelineRepository({
      getClient: () => this.clientMgr.getClient(),
      // optional filters (keep only message-like events in repo if you want)
      shouldIncludeEvent: (ev) =>
        ev.getType() === 'm.room.message' || ev.getType() === 'm.room.encrypted',
      // decryption hook (SDK method is optional across versions)
      tryDecryptEvent: async (ev) => {
        const c = this.clientMgr.getClient() as any;
        if (c?.decryptEventIfNeeded) await c.decryptEventIfNeeded(ev);
      },
      pageSize: 20,
    })
  );
  private queue = new OutgoingMessageQueue(() => this.clientMgr.getClient());
  private binder = new MatrixEventBinder(
    () => this.clientMgr.getClient(),
    () => this.hydrationState,
    this.timelineSvc,
    this.queue
  );

  private constructor() {}

  public static getInstance(): MatrixViewModel {
    if (!MatrixViewModel.instance) {
      MatrixViewModel.instance = new MatrixViewModel();
    }
    return MatrixViewModel.instance;
  }

  /* ---------- Public API (unchanged) ---------- */

  getSettingsComponent(): any {
    return null;
  }
  getModuleName(): string {
    return 'Matrix';
  }

  public isLoggedIn(): boolean {
    const c = this.clientMgr.getClient();
    return !!c && c.isLoggedIn();
  }

  public getTimelineItems(): Writable<IMatrixTimelineItem[]> {
    return this.timelineSvc.getTimelineItemsStore();
  }

  public getCurrentUserId(): string {
    return this.clientMgr.getClient()?.getUserId() || 'unknown';
  }

  public async getRoomMessages(roomId: string, fromToken: string | null, limit = 20) {
    return this.timelineSvc.getRoomMessages(roomId, fromToken, limit);
  }
  public async loadOlderMessages(roomId: string, fromToken?: string | null, limit = 20) {
    return this.timelineSvc.loadOlderMessages(roomId, fromToken, limit);
  }
  public clearRoomPaginationTokens(roomId: string) {
    this.timelineSvc.clearRoomPaginationTokens(roomId);
  }

  public async verifyCurrentDevice(): Promise<void> {
    await this.cryptoMgr.verifyCurrentDevice();
  }

  public getOpenIdToken(): Promise<matrixSdk.IOpenIDToken> {
    const c = this.clientMgr.getClient();
    if (!c) throw new Error('Matrix client not initialized.');
    return c.getOpenIdToken();
  }

  /* ---------- Orchestration ---------- */

  async initialize(): Promise<void> {
    (logger as any).setLevel('warn');

    const restored = this.sessionStore.restore();
    if (!restored?.accessToken || !restored.userId || !restored.homeserverUrl) {
      // no session; defer to login()
      return;
    }

    const cryptoCallbacks: CryptoCallbacks = {};
    if (matrixSettings.recoveryKey?.trim()) {
      (cryptoCallbacks as any).getSecretStorageKey = async ({
        keys,
      }: {
        keys: Record<string, any>;
      }) => {
        const keyId = Object.keys(keys)[0];
        if (!keyId) return null;
        const decoded = await decodeRecoveryKey(matrixSettings.recoveryKey!.trim());
        return [keyId, decoded];
      };
    }

    // build client, init, start, bind
    this.clientMgr.createFromSession(restored, cryptoCallbacks);
    await this.clientMgr.initCryptoIfNeeded();
    this.binder.bind();

    if (!this.clientMgr.isStarted()) {
      await this.clientMgr.start();
    }

    this.hydrationState = 'syncing';
    await this.clientMgr.waitForPrepared();

    this.hydrationState = 'decrypting';
    await this.cryptoMgr.ensureVerificationAndKeys();
    await this.cryptoMgr.debugSecrets();
    await this.cryptoMgr.restoreFromRecoveryKey();
    await this.cryptoMgr.retryDecryptAllRooms();

    await this.timelineSvc.fetchAndSetTimelineItems();

    this.hydrationState = 'ready';
    await this.timelineSvc.flushPendingLiveEvents();
  }

  async login(homeserverUrl: string, username: string, password: string): Promise<void> {
    try {
      // reset any previous client/session
      await this.clientMgr.stop();

      this.clientMgr.createForHomeserver(homeserverUrl);
      const c = this.clientMgr.getClient();
      if (!c) throw new Error('Failed to create Matrix client');
      const loginResponse = await c.login('m.login.password', { user: username, password });
      c.setAccessToken(loginResponse.access_token);

      const session: MatrixSessionData = {
        homeserverUrl,
        userId: loginResponse.user_id,
        accessToken: loginResponse.access_token,
        deviceId: loginResponse.device_id,
      };
      this.sessionStore.save(session);

      await this.initialize();
    } catch (error) {
      console.error('Matrix login failed:', error);
      throw error;
    }
  }

  /* ---------- Messaging ---------- */

  async sendMessage(roomId: string, messageContent: string): Promise<void> {
    const client = this.clientMgr.getClient();
    if (!client) {
      console.error('Cannot send message: Matrix client not initialized.');
      return;
    }
    this.queue.enqueue(roomId, 'm.room.message', { body: messageContent, msgtype: 'm.text' });
    this.queue.process();
  }
}
