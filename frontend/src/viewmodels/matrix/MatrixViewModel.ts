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
import { RoomAvatarService } from './core/RoomAvatarService';

import { MatrixSessionStore, type MatrixSessionData } from './core/MatrixSessionStore';
import { MatrixClientManager } from './core/MatrixClientManager';
import { OutgoingMessageQueue } from './core/OutgoingMessageQueue';
import { MatrixEventBinder } from './core/MatrixEventBinder';
import { MatrixCryptoManager } from './core/MatrixCryptoManager';
import { MatrixDataStore } from './core/MatrixDataStore';
import { MatrixDataLayer } from './core/MatrixDataLayer';

export class MatrixViewModel implements IModuleViewModel {
  private static instance: MatrixViewModel;

  // lifecycle / state
  private hydrationState: 'idle' | 'syncing' | 'decrypting' | 'ready' = 'idle';

  // composition
  private sessionStore = new MatrixSessionStore();
  private clientMgr = new MatrixClientManager();
  private cryptoMgr = new MatrixCryptoManager({ getClient: () => this.clientMgr.getClient() });
  private dataStore = new MatrixDataStore();
  private dataLayer = new MatrixDataLayer(this.dataStore, {
    getClient: () => this.clientMgr.getClient(),
    shouldIncludeEvent: (ev) =>
      ev.getType() === 'm.room.message' || ev.getType() === 'm.room.encrypted',
    tryDecryptEvent: async (ev) => {
      const c = this.clientMgr.getClient();
      if (c?.decryptEventIfNeeded) await c.decryptEventIfNeeded(ev);
    },
    pageSize: 20,
  });
  private avatarSvc = new RoomAvatarService(
    { getClient: () => this.clientMgr.getClient() },
    this.dataStore,
    { maxMemEntries: 200, maxDbEntries: 200 }
  );
  private timelineSvc = new MatrixTimelineService(
    {
      getClient: () => this.clientMgr.getClient(),
      isStarted: () => this.clientMgr.isStarted(),
      getHydrationState: () => this.hydrationState,
    },
    this.dataStore,
    this.dataLayer,
    this.avatarSvc
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
    return this.dataStore.getCurrentUserId() || 'unknown';
  }

  public getCurrentUserDisplayName(): string {
    return this.dataStore.getCurrentUserDisplayName() || 'unknown';
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

  // Media cache management
  public clearMediaCache(): void {
    this.timelineSvc.clearMediaCache();
  }

  // Query cached events by room directly from IndexedDB cache (new)
  public async queryCachedRoomEvents(roomId: string, limit = 50, beforeTs?: number) {
    return this.dataLayer.queryEventsByRoom(roomId, limit, beforeTs);
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

    // Load persistent cache via data layer (rooms, events, tokens)
    const hadCache = this.dataLayer.loadFromCache(5, () => {
      try {
        console.log('[MatrixVM] onHydrated → immediate cache-only render');
        // Render without waiting for any timers or client readiness
        this.timelineSvc.fetchAndSetTimelineItems(true);
        this.hydrationState = 'ready';
        console.log('[MatrixVM] onHydrated → scheduleTimelineRefresh(0)');
      } catch (err) {
        console.error('onHydrated error:', err);
      }
    });

    console.time('[MatrixVM] cryptoCallbacks setup');
    const cryptoCallbacks: CryptoCallbacks = {};
    if (matrixSettings.recoveryKey?.trim()) {
      cryptoCallbacks.getSecretStorageKey = async ({ keys }: { keys: Record<string, any> }) => {
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

    // Initialize current user info in our store (display name may be filled later if desired)
    if (restored.userId) {
      this.dataStore.setCurrentUser(restored.userId);
      this.dataLayer.saveToCache();
    }

    console.time('[MatrixVM] initRustCrypto');
    await this.clientMgr.initCryptoIfNeeded();
    console.timeEnd('[MatrixVM] initRustCrypto');

    console.time('[MatrixVM] bind listeners');
    this.binder.bind();
    console.timeEnd('[MatrixVM] bind listeners');

    if (!this.clientMgr.isStarted()) {
      console.time('[MatrixVM] startClient');

      const minimalFilterDef: matrixSdk.IFilterDefinition = {
        room: {
          timeline: {
            limit: 30,
            types: ['m.room.message', 'm.room.encrypted'],
          },
          state: { lazy_load_members: true },
          ephemeral: { types: [] },
        },
        presence: { types: [] },
        event_format: 'client',
        event_fields: ['type', 'content', 'sender', 'origin_server_ts', 'event_id', 'room_id'],
      };

      // Wrap in a Filter instance
      const filter = new matrixSdk.Filter(this.clientMgr.getClient()?.getUserId(), undefined);
      filter.setDefinition(minimalFilterDef);

      await this.clientMgr.start({
        filter: filter,
        pollTimeout: 0,
        lazyLoadMembers: true,
        initialSyncLimit: 5,
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

    // Populate rooms into the store once the client is prepared
    this.dataLayer.ingestInitialRooms();

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

    // Background decryption updates are handled via binder events; no bulk retries here.

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
