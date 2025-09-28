import * as matrixSdk from 'matrix-js-sdk';
import loglevel from 'loglevel';
import { type Writable } from 'svelte/store';
import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import type { TimelineItem } from '@/models/shared/TimelineItem';
import { matrixSettings } from '@/viewmodels/matrix/MatrixSettings';
import {
  MatrixTimelineService,
  type MatrixMessage,
} from '@/viewmodels/matrix/MatrixTimelineService';
import { AvatarService } from './core/AvatarService';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixSessionStore, type MatrixSessionData } from './core/MatrixSessionStore';
import { MatrixClientManager } from './core/MatrixClientManager';
import { MatrixCryptoManager } from './core/MatrixCryptoManager';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import { createNotificationService } from '@/notifications/NotificationService';
import { MatrixMessagingService } from './core/MatrixMessagingService';
import { MatrixPushRuleService } from './core/MatrixPushRuleService';
import type { MatrixReplyContext } from './types';
import { MatrixSlidingSyncService } from './core/MatrixSlidingSyncService';
import { matrixNative } from '@/plugins/matrixNative';

export class MatrixViewModel implements IModuleViewModel {
  private static instance: MatrixViewModel;

  // lifecycle / state
  private hydrationState: 'idle' | 'syncing' | 'decrypting' | 'ready' = 'idle';
  private matrixReadyPromise: Promise<void>;
  private resolveMatrixReady: (() => void) | null = null;
  private matrixReadyResolved = false;
  private initPromise: Promise<void> | null = null;
  private hasInitialized = false;

  // composition
  private sessionStore = new MatrixSessionStore();
  private clientMgr = new MatrixClientManager();
  private cryptoMgr = new MatrixCryptoManager({
    getClient: () => this.clientMgr.getClient(),
    getRuntimeFlavor: () => this.clientMgr.getRuntimeFlavor(),
  });
  private dataLayer = new MatrixDataLayer({
    getClient: () => this.clientMgr.getClient(),
    shouldIncludeEvent: (ev) =>
      ev.getType() === 'm.room.message' || ev.getType() === 'm.room.encrypted',
    tryDecryptEvent: async (ev) => {
      const c = this.clientMgr.getClient();
      if (c?.decryptEventIfNeeded) await c.decryptEventIfNeeded(ev);
    },
    waitForPrepared: () => this.waitForMatrixReady(),
    pageSize: 20,
  });
  private slidingSyncSvc = new MatrixSlidingSyncService({
    getClient: () => this.clientMgr.getClient(),
    dataLayer: this.dataLayer,
  });
  private avatarSvc = new AvatarService(
    { getClient: () => this.clientMgr.getClient() },
    this.dataLayer,
    { maxMemEntries: 200, maxDbEntries: 5000 }
  );
  private notificationSvc = createNotificationService();
  private messagingSvc = new MatrixMessagingService(() => this.clientMgr.getClient());
  private timelineSvc = new MatrixTimelineService(
    {
      getClient: () => this.clientMgr.getClient(),
      isStarted: () => this.clientMgr.isStarted(),
      getHydrationState: () => this.hydrationState,
    },
    this.dataLayer,
    this.avatarSvc,
    this.notificationSvc
  );
  private pushRuleSvc = new MatrixPushRuleService(() => this.clientMgr.getClient());

  private constructor() {
    this.matrixReadyPromise = new Promise<void>((resolve) => {
      this.resolveMatrixReady = resolve;
    });
  }

  private resetMatrixReadyPromise(): void {
    this.matrixReadyResolved = false;
    this.matrixReadyPromise = new Promise<void>((resolve) => {
      this.resolveMatrixReady = resolve;
    });
  }

  private markMatrixReady(): void {
    if (this.matrixReadyResolved) return;
    this.matrixReadyResolved = true;
    if (this.resolveMatrixReady) {
      this.resolveMatrixReady();
      this.resolveMatrixReady = null;
    }
  }

  private async waitForMatrixReady(): Promise<void> {
    if (this.matrixReadyResolved) return;
    await this.matrixReadyPromise;
  }

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

  public getTimelineItems(): Writable<TimelineItem[]> {
    return this.timelineSvc.getTimelineItemsStore();
  }

  public getMediaVersion(): Writable<number> {
    return this.timelineSvc.getMediaVersionStore();
  }

  public getCurrentUserId(): string {
    return this.dataLayer.getCurrentUserId() || 'unknown';
  }

  public getCurrentUserDisplayName(): string {
    return this.dataLayer.getCurrentUserDisplayName() || 'unknown';
  }

  public async getRoomMessages(roomId: string, beforeIndex: number | null, limit = 20) {
    return this.timelineSvc.getRoomMessages(roomId, beforeIndex, limit);
  }

  public onRepoEvent(
    listener: (ev: RepoEvent, room: matrixSdk.Room | null, meta?: { isLive?: boolean }) => void
  ): () => void {
    return this.dataLayer.onRepoEvent(listener);
  }

  public onReadReceipt(
    listener: (roomId: string, eventId: string, userId: string) => void
  ): () => void {
    return this.dataLayer.onReadReceipt(listener);
  }

  public async mapRepoEventsToMessages(events: RepoEvent[]): Promise<MatrixMessage[]> {
    return this.timelineSvc.mapRepoEventsToMessages(events);
  }

  public async getRoomMembers(roomId: string) {
    return this.dataLayer.getRoomMembers(roomId);
  }

  /** Number of other joined members in the room (excluding self). */
  public async getRecipientCount(roomId: string): Promise<number> {
    try {
      const members = await this.dataLayer.getRoomMembers(roomId);
      const selfId = this.getCurrentUserId();
      return (members || [])
        .filter((m: any) => (m.membership ? m.membership === 'join' : true))
        .filter((m: any) => m.userId !== selfId).length;
    } catch (e) {
      console.error('[MatrixDataLayer] getRecipientCount failed', e);
      return 0;
    }
  }

  /** Min read timestamp among other members for status rendering. */
  public async getMinOtherReadTs(roomId: string): Promise<number> {
    return this.dataLayer.getMinOtherReadTs(roomId);
  }

  // Trigger a background sync of a single room (members, read snapshots, metadata)
  public syncRoom(roomId: string): Promise<void> {
    return this.dataLayer.syncRoom(roomId);
  }

  public async markRoomAsRead(roomId: string): Promise<void> {
    await this.dataLayer.markRoomAsRead(roomId);
    this.timelineSvc.setRoomUnread(roomId, 0);
  }

  // Media cache management
  public clearMediaCache(): void {
    this.timelineSvc.clearMediaCache();
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
    if (this.hasInitialized) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    const promise = this.initializeInternal();
    this.initPromise = promise;
    try {
      await promise;
    } finally {
      if (this.initPromise === promise) {
        this.initPromise = null;
      }
    }
  }

  private async initializeInternal(): Promise<void> {
    // Set global log level via loglevel directly (avoids unsafe casts)
    loglevel.setLevel('warn');
    console.time('[MatrixVM] initialize total');
    this.resetMatrixReadyPromise();
    this.slidingSyncSvc.stop();

    const restored = this.sessionStore.restore();
    if (!restored?.accessToken || !restored.userId || !restored.homeserverUrl) {
      console.warn('[MatrixVM] no session data → skipping init');
      return;
    }

    await this.dataLayer.init();
    await this.timelineSvc.initTimeline({ offlineOnly: true }).catch((err) => {
      console.warn('Failed to hydrate cached timeline:', err);
    });
    void this.notificationSvc.requestPermission();

    console.time('[MatrixVM] create client');
    const getRecoveryKey = () => matrixSettings.recoveryKey?.trim();
    await this.clientMgr.createFromSession(restored, getRecoveryKey);
    console.timeEnd('[MatrixVM] create client');

    // Initialize current user info in our store (display name may be filled later if desired)
    if (restored.userId) {
      this.dataLayer.setCurrentUser(restored.userId);
    }

    console.time('[MatrixVM] initRustCrypto');
    await this.clientMgr.initCryptoIfNeeded();
    console.timeEnd('[MatrixVM] initRustCrypto');

    console.time('[MatrixVM] bind data layer');
    this.dataLayer.bind();
    console.timeEnd('[MatrixVM] bind data layer');

    if (!this.clientMgr.isStarted()) {
      console.time('[MatrixVM] startClient');

      const minimalFilterDef: matrixSdk.IFilterDefinition = {
        room: {
          timeline: {
            limit: 30,
            types: ['m.room.message', 'm.room.encrypted'],
          },
          state: { lazy_load_members: true },
          // Include receipts so cross-device read state propagates promptly
          ephemeral: { types: ['m.receipt'] },
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
        pollTimeout: 30000,
        lazyLoadMembers: true,
        initialSyncLimit: 5,
      });
      console.timeEnd('[MatrixVM] startClient');
    }

    try {
      await this.slidingSyncSvc.init();
    } catch (err) {
      console.warn('[MatrixVM] sliding sync init failed', err);
    }
    this.slidingSyncSvc.start();

    // Only set to 'syncing' if we haven't already set it to 'ready' from cache
    if (this.hydrationState !== 'ready') {
      this.hydrationState = 'syncing';
    }

    const slidingReadyPromise = this.slidingSyncSvc
      .waitUntilReady()
      .catch((err) => {
        console.warn('[MatrixVM] sliding sync failed to signal readiness', err);
      });
    const legacyPreparedPromise = this.clientMgr
      .waitForPrepared()
      .catch((err) => {
        console.warn('[MatrixVM] waitForPrepared failed', err);
      });

    console.time('[MatrixVM] waitForMatrixReady');
    await Promise.race([slidingReadyPromise, legacyPreparedPromise]);
    this.markMatrixReady();
    console.timeEnd('[MatrixVM] waitForMatrixReady');

    void legacyPreparedPromise.then(() => this.markMatrixReady());

    console.time('[MatrixVM] ensurePushRulesLoaded');
    try {
      await this.pushRuleSvc.ensurePushRulesLoaded();
    } catch (err) {
      console.warn('[MatrixVM] Failed to preload push rules', err);
    } finally {
      console.timeEnd('[MatrixVM] ensurePushRulesLoaded');
    }

    await this.timelineSvc.initTimeline().catch((err) => {
      console.warn('Failed to initialize timeline:', err);
    });

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

    this.hydrationState = 'ready';
    console.timeEnd('[MatrixVM] initialize total');

    // Reflect unread updates from the data layer into the UI.
    this.dataLayer.onUnreadChange((roomId, unread) => {
      this.timelineSvc.setRoomUnread(roomId, unread);
    });

    this.hasInitialized = true;
  }

  async login(homeserverUrl: string, username: string, password: string): Promise<void> {
    try {
      // reset any previous client/session
      await this.clientMgr.stop();
      this.hasInitialized = false;

      await this.clientMgr.createForHomeserver(homeserverUrl);

      if (this.clientMgr.getRuntimeFlavor() === 'native') {
        const loginResult = await matrixNative.login({
          username,
          password,
          deviceName: 'Messie Android',
        });

        const session: MatrixSessionData = {
          homeserverUrl: loginResult.homeserverUrl ?? homeserverUrl,
          userId: loginResult.userId,
          accessToken: loginResult.accessToken,
          deviceId: loginResult.deviceId,
          refreshToken: loginResult.refreshToken,
        };
        this.sessionStore.save(session);
        await this.initialize();
        return;
      }

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

  async requestPasswordReset(
    homeserverUrl: string,
    email: string,
    nextLink: string
  ): Promise<{ sid: string; clientSecret: string }> {
    const clientSecret = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
    const client = matrixSdk.createClient({ baseUrl: homeserverUrl });
    const res = await client.requestPasswordEmailToken(email, clientSecret, 1, nextLink);
    // Persist mapping so we can finish the flow after email confirmation
    try {
      localStorage.setItem(`matrix:pwdreset:${res.sid}:client_secret`, clientSecret);
      localStorage.setItem('matrixHomeserverUrl', homeserverUrl);
    } catch {
      // ignore storage errors (e.g., SSR or storage disabled)
    }
    return { sid: res.sid, clientSecret };
  }

  async resetPassword(
    homeserverUrl: string,
    clientSecret: string,
    sid: string,
    newPassword: string
  ): Promise<void> {
    const client = matrixSdk.createClient({ baseUrl: homeserverUrl });
    await client.setPassword(
      {
        type: 'm.login.email.identity',
        threepid_creds: { client_secret: clientSecret, sid },
      },
      newPassword,
      true
    );
  }

  /* ---------- Messaging ---------- */

  async pickMedia(): Promise<File | undefined> {
    return this.messagingSvc.pickMedia();
  }

  async pickFile(): Promise<File | undefined> {
    return this.messagingSvc.pickFile();
  }

  async sendMedia(roomId: string): Promise<void> {
    await this.messagingSvc.sendMedia(roomId);
  }

  async sendFile(roomId: string): Promise<void> {
    await this.messagingSvc.sendFile(roomId);
  }

  async sendAttachment(
    roomId: string,
    file: File,
    caption?: string,
    replyTo?: MatrixReplyContext
  ): Promise<void> {
    await this.messagingSvc.sendAttachment(roomId, file, caption, replyTo);
  }

  async sendMessage(
    roomId: string,
    messageContent: string,
    replyTo?: MatrixReplyContext
  ): Promise<void> {
    await this.messagingSvc.sendMessage(roomId, messageContent, replyTo);
  }

  async editMessage(
    roomId: string,
    targetEventId: string,
    messageContent: string,
    replyToEventId?: string,
    msgtype?: string
  ): Promise<void> {
    await this.messagingSvc.editMessage(
      roomId,
      targetEventId,
      messageContent,
      replyToEventId,
      msgtype
    );
  }

  /* ---------- Push rules & notifications ---------- */

  public async isRoomMuted(roomId: string): Promise<boolean> {
    return this.pushRuleSvc.isRoomMuted(roomId);
  }

  public async refreshRoomMuteState(roomId: string): Promise<boolean> {
    return this.pushRuleSvc.refreshRoomMuteState(roomId);
  }

  public async setRoomMuted(roomId: string, mute: boolean): Promise<boolean> {
    return this.pushRuleSvc.setRoomMuted(roomId, mute);
  }
}
