import { type CryptoCallbacks } from 'matrix-js-sdk/lib/crypto-api';
import * as matrixSdk from 'matrix-js-sdk';
import { decodeRecoveryKey } from 'matrix-js-sdk/lib/crypto-api/recovery-key';
import { logger } from 'matrix-js-sdk/lib/logger.js';
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
import { OutgoingMessageQueue } from './core/OutgoingMessageQueue';
import { MatrixCryptoManager } from './core/MatrixCryptoManager';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import { BrowserNotificationService } from '@/notifications/NotificationService';
import { BrowserMediaService } from './core/MediaService';
import type { EncryptedFile } from 'matrix-js-sdk/lib/@types/media';

export class MatrixViewModel implements IModuleViewModel {
  private static instance: MatrixViewModel;

  // lifecycle / state
  private hydrationState: 'idle' | 'syncing' | 'decrypting' | 'ready' = 'idle';

  // composition
  private sessionStore = new MatrixSessionStore();
  private clientMgr = new MatrixClientManager();
  private cryptoMgr = new MatrixCryptoManager({ getClient: () => this.clientMgr.getClient() });
  private dataLayer = new MatrixDataLayer({
    getClient: () => this.clientMgr.getClient(),
    shouldIncludeEvent: (ev) =>
      ev.getType() === 'm.room.message' || ev.getType() === 'm.room.encrypted',
    tryDecryptEvent: async (ev) => {
      const c = this.clientMgr.getClient();
      if (c?.decryptEventIfNeeded) await c.decryptEventIfNeeded(ev);
    },
    waitForPrepared: () => this.clientMgr.waitForPrepared(),
    pageSize: 20,
  });
  private avatarSvc = new AvatarService(
    { getClient: () => this.clientMgr.getClient() },
    this.dataLayer,
    { maxMemEntries: 200, maxDbEntries: 5000 }
  );
  private notificationSvc = new BrowserNotificationService();
  private mediaSvc = new BrowserMediaService();
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
  private queue = new OutgoingMessageQueue(() => this.clientMgr.getClient());

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
    listener: (ev: RepoEvent, room: matrixSdk.Room, meta?: { isLive?: boolean }) => void
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
    // Set global log level via loglevel directly (avoids unsafe casts)
    loglevel.setLevel('warn');
    console.time('[MatrixVM] initialize total');

    const restored = this.sessionStore.restore();
    if (!restored?.accessToken || !restored.userId || !restored.homeserverUrl) {
      console.warn('[MatrixVM] no session data → skipping init');
      return;
    }

    await this.dataLayer.init();
    await this.timelineSvc.initTimeline().catch((err) => {
      console.warn('Failed to initialize timeline:', err);
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

    this.hydrationState = 'ready';
    console.timeEnd('[MatrixVM] initialize total');

    // Reflect unread updates from the data layer into the UI.
    this.dataLayer.onUnreadChange((roomId, unread) => {
      this.timelineSvc.setRoomUnread(roomId, unread);
    });
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

  async requestPasswordReset(
    homeserverUrl: string,
    email: string,
    nextLink: string,
  ): Promise<{ sid: string; clientSecret: string }> {
    const clientSecret =
      Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
    const client = matrixSdk.createClient({ baseUrl: homeserverUrl });
    const res = await client.requestPasswordEmailToken(email, clientSecret, 1, nextLink);
    // Persist mapping so we can finish the flow after email confirmation
    try {
      localStorage.setItem(
        `matrix:pwdreset:${res.sid}:client_secret`,
        clientSecret,
      );
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
    newPassword: string,
  ): Promise<void> {
    const client = matrixSdk.createClient({ baseUrl: homeserverUrl });
    await client.setPassword(
      {
        type: 'm.login.email.identity',
        threepid_creds: { client_secret: clientSecret, sid },
      },
      newPassword,
      true,
    );
  }

  /* ---------- Messaging ---------- */

  async pickMedia(): Promise<File | undefined> {
    return this.mediaSvc.pickMedia();
  }

  async pickFile(): Promise<File | undefined> {
    return this.mediaSvc.pickFile();
  }

  async sendMedia(roomId: string): Promise<void> {
    const file = await this.mediaSvc.pickMedia();
    if (!file) return;
    const caption =
      typeof window !== 'undefined'
        ? window.prompt('Add a caption (optional):') || undefined
        : undefined;
    await this.sendAttachment(roomId, file, caption);
  }

  async sendFile(roomId: string): Promise<void> {
    const file = await this.mediaSvc.pickFile();
    if (!file) return;
    const caption =
      typeof window !== 'undefined'
        ? window.prompt('Add a caption (optional):') || undefined
        : undefined;
    await this.sendAttachment(roomId, file, caption);
  }

  async sendAttachment(roomId: string, file: File, caption?: string): Promise<void> {
    const client = this.clientMgr.getClient();
    if (!client) {
      console.error('Cannot send media: Matrix client not initialized.');
      return;
    }

    const isEncryptedRoom = client.isRoomEncrypted(roomId);
    const msgtype = file.type.startsWith('image/')
      ? matrixSdk.MsgType.Image
      : file.type.startsWith('video/')
        ? matrixSdk.MsgType.Video
        : matrixSdk.MsgType.File;

    const content: any = {
      body: caption ?? '',
      filename: file.name || 'file',
      msgtype,
      info: { mimetype: file.type || 'application/octet-stream', size: file.size },
    };

    if (msgtype === matrixSdk.MsgType.Image) {
      const dims = await this.getImageSize(file).catch(() => undefined);
      if (dims) {
        content.info.w = dims.width;
        content.info.h = dims.height;
      }
    }

    try {
      if (isEncryptedRoom) {
        const enc = await this.encryptAttachment(file);
        const res = await client.uploadContent(new Blob([enc.data]), {
          type: 'application/octet-stream',
        });
        content.file = { ...enc.file, url: res.content_uri } as EncryptedFile;
      } else {
        const res = await client.uploadContent(file, { type: file.type });
        content.url = res.content_uri;
      }

      this.queue.enqueue(roomId, 'm.room.message', content);
      this.queue.process();
    } catch (e) {
      console.error('Failed to send media message', e);
    }
  }

  private async getImageSize(file: File): Promise<{ width: number; height: number }> {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        resolve({ width: img.width, height: img.height });
        URL.revokeObjectURL(url);
      };
      img.onerror = (err) => {
        URL.revokeObjectURL(url);
        reject(err);
      };
      img.src = url;
    });
  }

  private async encryptAttachment(
    file: File
  ): Promise<{ data: ArrayBuffer; file: Omit<EncryptedFile, 'url'> }> {
    const data = await file.arrayBuffer();
    const iv = crypto.getRandomValues(new Uint8Array(16));
    const keyBytes = crypto.getRandomValues(new Uint8Array(32));
    const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-CTR', true, [
      'encrypt',
      'decrypt',
    ]);
    const cipher = await crypto.subtle.encrypt(
      { name: 'AES-CTR', counter: iv, length: 64 },
      key,
      data
    );
    const hashBuf = await crypto.subtle.digest('SHA-256', cipher);
    const keyJwk = (await crypto.subtle.exportKey('jwk', key)) as EncryptedFile['key'];
    // Ensure required fields for Matrix spec
    keyJwk.alg = 'A256CTR';
    keyJwk.key_ops = ['encrypt', 'decrypt'];
    keyJwk.ext = true;

    // Standard base64 (alphabet +/) without padding, per EncryptedFile spec.
    const toBase64Unpadded = (buf: ArrayBuffer | Uint8Array) => {
      const bytes = buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf;
      let binary = '';
      for (const b of bytes) binary += String.fromCharCode(b);
      return btoa(binary).replace(/=+$/, '');
    };

    return {
      data: cipher,
      file: {
        v: 'v2',
        key: keyJwk,
        iv: toBase64Unpadded(iv),
        hashes: { sha256: toBase64Unpadded(hashBuf) },
      },
    };
  }

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
