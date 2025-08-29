import { type CryptoCallbacks } from 'matrix-js-sdk/lib/crypto-api';
import * as matrixSdk from 'matrix-js-sdk';
import { decodeRecoveryKey } from 'matrix-js-sdk/lib/crypto-api/recovery-key';
import { logger } from 'matrix-js-sdk/lib/logger.js';

import { writable, type Writable } from 'svelte/store';

import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import {
  MatrixTimelineItem,
  type IMatrixTimelineItem,
} from '@/viewmodels/matrix/MatrixTimelineItem';
import { matrixSettings } from '@/viewmodels/matrix/MatrixSettings';
import { MatrixTimelineService } from '@/viewmodels/matrix/MatrixTimelineService';
import { RoomPreviewCache } from '@/viewmodels/matrix/RoomPreviewCache';

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

  public getCurrentUserDisplayName(): string {
    const client = this.clientMgr.getClient();
    if (!client) return 'unknown';
    const userId = client.getUserId();
    if (!userId) return 'unknown'; // Handle null userId
    const room = client.getVisibleRooms()[0]; // Assuming any visible room will have the member info
    return room?.getMember(userId)?.rawDisplayName || userId || 'unknown';
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
    console.time('[MatrixVM] initialize total');

    const restored = this.sessionStore.restore();
    if (!restored?.accessToken || !restored.userId || !restored.homeserverUrl) {
      console.warn('[MatrixVM] no session data → skipping init');
      return;
    }

    const cache = new RoomPreviewCache();
    const cached = cache.load();
    if (cached.length) {
      console.log(`[MatrixVM] restoring ${cached.length} room previews from cache`);
      const items = cached.map(
        (p) =>
          new MatrixTimelineItem({
            id: p.id,
            type: 'matrix',
            title: p.title,
            description: p.description,
            timestamp: p.timestamp,
          })
      );
      this.timelineSvc.getTimelineItemsStore().set(items);
      this.hydrationState = 'ready'; // show UI now
      console.log('[MatrixVM] hydrationState → ready (from cache)');
    } else {
      console.log('[MatrixVM] no room previews in cache');
    }

    console.time('[MatrixVM] cryptoCallbacks setup');
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
    console.timeEnd('[MatrixVM] cryptoCallbacks setup');

    console.time('[MatrixVM] create client');
    await this.clientMgr.createFromSession(restored, cryptoCallbacks);
    console.timeEnd('[MatrixVM] create client');

    console.time('[MatrixVM] initRustCrypto');
    await this.clientMgr.initCryptoIfNeeded();
    console.timeEnd('[MatrixVM] initRustCrypto');

    console.time('[MatrixVM] bind listeners');
    this.binder.bind();
    console.timeEnd('[MatrixVM] bind listeners');

    if (!this.clientMgr.isStarted()) {
      console.time('[MatrixVM] startClient');

      // const minimalFilterDef: matrixSdk.IFilterDefinition = {
      //   room: {
      //     timeline: {
      //       limit: 1,
      //       types: ['m.room.message', 'm.room.encrypted'],
      //     },
      //     state: { lazy_load_members: true },
      //     ephemeral: { types: [] },
      //   },
      //   presence: { types: [] },
      //   event_format: 'client',
      //   event_fields: ['type', 'content', 'sender', 'origin_server_ts', 'event_id', 'room_id'],
      // };

      // // Wrap in a Filter instance
      // const filter = new matrixSdk.Filter(this.clientMgr.getClient()?.getUserId(), undefined);
      // filter.setDefinition(minimalFilterDef);

      await this.clientMgr.start({
        // filter: filter,
        // pollTimeout: 0,
        // lazyLoadMembers: true,
        // initialSyncLimit: 1,
      });
      console.timeEnd('[MatrixVM] startClient');
    }

    // Only set to 'syncing' if we haven't already set it to 'ready' from cache
    if (this.hydrationState !== 'ready') {
      this.hydrationState = 'syncing';
    }
    console.time('[MatrixVM] waitForPrepared');
    await this.clientMgr.waitForPrepared();
    console.timeEnd('[MatrixVM] waitForPrepared');

    this.hydrationState = 'decrypting';
    console.time('[MatrixVM] crypto.ensureVerificationAndKeys');
    await this.cryptoMgr.ensureVerificationAndKeys();
    console.timeEnd('[MatrixVM] crypto.ensureVerificationAndKeys');

    console.time('[MatrixVM] crypto.debugSecrets');
    await this.cryptoMgr.debugSecrets();
    console.timeEnd('[MatrixVM] crypto.debugSecrets');

    console.time('[MatrixVM] crypto.restoreFromRecoveryKey');
    await this.cryptoMgr.restoreFromRecoveryKey();
    console.timeEnd('[MatrixVM] crypto.restoreFromRecoveryKey');

    console.time('[MatrixVM] crypto.retryDecryptAllRooms');
    await this.cryptoMgr.retryDecryptAllRooms();
    console.timeEnd('[MatrixVM] crypto.retryDecryptAllRooms');

    console.time('[MatrixVM] fetch timeline items');
    await this.timelineSvc.fetchAndSetTimelineItems();
    console.timeEnd('[MatrixVM] fetch timeline items');

    this.hydrationState = 'ready';
    console.time('[MatrixVM] flush pending events');
    await this.timelineSvc.flushPendingLiveEvents();
    console.timeEnd('[MatrixVM] flush pending events');

    console.timeEnd('[MatrixVM] initialize total');
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
