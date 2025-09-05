import { writable, type Writable } from 'svelte/store';
import type { IModuleViewModel } from '../shared/IModuleViewModel';
import { createClient, createMockClient, type MatrixLiteClient } from '@/matrix-lite/client';
import type { LiteMessage, LiteRoom, LiteMember } from '@/matrix-lite/types';
import { loadSession, type LiteSession, clearSession } from '@/matrix-lite/runtime/session';
import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import { matrixSettings } from './MatrixSettings';
import type { MatrixMessage } from './MatrixTimelineService';

/**
 * Simplified Matrix ViewModel backed by mock data.
 * Provides the same public API as the real MatrixViewModel but
 * operates entirely in-memory.
 */
export class MatrixLiteViewModel implements IModuleViewModel {
  private static instance: MatrixLiteViewModel;

  private session: LiteSession | null = loadSession();
  private client: MatrixLiteClient = this.session
    ? createClient(this.session.homeserverUrl)
    : createMockClient();
  private timeline: Writable<IMatrixTimelineItem[]> = writable([]);
  private rooms: LiteRoom[] = [];
  private currentUser = this.session?.userId || '@alice:example.org';
  private repoListeners = new Set<(ev: any, room: any) => void>();
  private syncActive = false;
  private stopToDevice: (() => void) | null = null;

  private constructor() {}

  public static getInstance(): MatrixLiteViewModel {
    if (!MatrixLiteViewModel.instance) {
      MatrixLiteViewModel.instance = new MatrixLiteViewModel();
    }
    return MatrixLiteViewModel.instance;
  }

  async initialize(): Promise<void> {
    if (!this.session) {
      console.warn('[compat-mock] MatrixLiteViewModel.initialize()');
    }
    // If already logged in (session present), initialize crypto to upload/query keys
    if (this.session) {
      try {
        await this.client.initCrypto();
      } catch (err) {
        console.warn('[matrix-lite] initCrypto on initialize failed', err);
      }
    }
    this.rooms = await this.client.listRooms();
    this.startSyncListener();
    const items = this.rooms.map((r) =>
      new MatrixTimelineItem({
        id: r.id,
        type: 'matrix',
        title: r.name,
        description: '',
        timestamp: Date.now(),
      })
    );
    this.timeline.set(items);
  }


  getTimelineItems(): Writable<IMatrixTimelineItem[]> {
    return this.timeline;
  }

  getSettingsComponent(): any {
    return null;
  }

  getModuleName(): string {
    return 'Matrix';
  }

  isLoggedIn(): boolean {
    return !!this.session;
  }

  getCurrentUserId(): string {
    return this.currentUser;
  }

  getCurrentUserDisplayName(): string {
    return 'Alice';
  }

  async login(homeserverUrl: string, username: string, password: string): Promise<void> {
    this.client = createClient(homeserverUrl);
    await this.client.login(username, password);
    this.session = loadSession();
    this.currentUser = this.session?.userId || username;
    await this.initialize();
  }

  async logout(): Promise<void> {
    await this.client.logout();
    clearSession();
    this.session = null;
    this.currentUser = '@alice:example.org';
    this.timeline.set([]);
    this.rooms = [];
    this.client = createMockClient();
    this.stopToDevice?.();
    this.stopToDevice = null;
    this.syncActive = false;
  }

  async getRoomMessages(
    roomId: string,
    beforeToken: any,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    const token = typeof beforeToken === 'string' ? beforeToken : undefined;
    // Fetch members once to resolve display names and avatars
    let members: LiteMember[] = [];
    try {
      members = await this.client.getRoomMembers(roomId);
    } catch {}
    const byUser = new Map<string, LiteMember>();
    for (const m of members) byUser.set(m.userId, m);

    const { messages: page, nextToken } = await this.client.getRoomMessages(
      roomId,
      token,
      limit
    );
    const msgs: MatrixMessage[] = page.map((m) => {
      const member = byUser.get(m.sender);
      const senderDisplayName = member?.displayName || m.sender;
      const senderAvatarUrl = member?.avatarUrl ? this.mxcToHttp(member.avatarUrl, 32, 32) : undefined;
      return {
        id: m.id,
        sender: m.sender,
        senderDisplayName,
        senderAvatarUrl,
        description: m.content,
        timestamp: m.timestamp,
        isSelf: m.sender === this.currentUser,
      } as MatrixMessage;
    });
    return { messages: msgs, nextBatch: nextToken ?? null };
  }

  onRepoEvent(listener: (ev: any, room: any) => void): () => void {
    this.repoListeners.add(listener);
    return () => this.repoListeners.delete(listener);
  }

  async mapRepoEventsToMessages(events: any[]): Promise<MatrixMessage[]> {
    return events as MatrixMessage[];
  }

  async getRoomMembers(roomId: string): Promise<LiteMember[]> {
    return this.client.getRoomMembers(roomId);
  }

  private startSyncListener(): void {
    if (this.stopToDevice) return;
    this.stopToDevice = this.client.onToDevice((ev) => {
      console.log('[matrix-lite] to-device event (VM)', ev);
    });
    this.syncActive = this.client.isSyncing();
  }

  isSyncing(): boolean {
    return this.syncActive;
  }

  private mxcToHttp(mxcUrl: string, w = 32, h = 32): string | undefined {
    try {
      if (!mxcUrl || typeof mxcUrl !== 'string') return undefined;
      if (!mxcUrl.startsWith('mxc://')) return mxcUrl;
      const hs = this.session?.homeserverUrl || '';
      const base = hs.replace(/\/$/, '');
      const rest = mxcUrl.slice('mxc://'.length);
      const slash = rest.indexOf('/');
      if (slash <= 0) return undefined;
      const server = encodeURIComponent(rest.slice(0, slash));
      const mediaId = encodeURIComponent(rest.slice(slash + 1));
      const qs = new URLSearchParams({ width: String(w), height: String(h), method: 'crop' });
      return `${base}/_matrix/media/v3/thumbnail/${server}/${mediaId}?${qs.toString()}`;
    } catch {
      return undefined;
    }
  }

  clearMediaCache(): void {
    // no-op for mock
  }

  async sendMessage(roomId: string, messageContent: string): Promise<void> {
    await this.client.sendMessage(roomId, messageContent);
    for (const l of this.repoListeners) {
      try {
        l({ type: 'message' }, { id: roomId });
      } catch (err) {
        console.error(err);
      }
    }
  }

  async getOpenIdToken(): Promise<any> {
    console.warn('[compat-mock] getOpenIdToken() called');
    return {
      access_token: 'mock-token',
      matrix_server_name: 'example.org',
      expires_in: 3600,
      token_type: 'Bearer',
    };
  }

  async verifyCurrentDevice(): Promise<void> {
    console.warn('[compat-mock] verifyCurrentDevice() called');
  }

  async restoreFromRecoveryKey(): Promise<void> {
    try {
      const key = matrixSettings.recoveryKey?.trim();
      if (!key) {
        console.warn('[matrix-lite] No recovery key set in settings');
        return;
      }
      const imported = await this.client.restoreBackupWithRecoveryKey(key);
      console.log(`[backup-restore] Imported ${imported} sessions`);
    } catch (err) {
      console.warn('[matrix-lite] restoreFromRecoveryKey failed', err);
    }
  }
}
