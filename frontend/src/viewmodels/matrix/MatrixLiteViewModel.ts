import { writable, type Writable } from 'svelte/store';
import type { IModuleViewModel } from '../shared/IModuleViewModel';
import { createMockClient, type MatrixLiteClient } from '@/matrix-lite/client';
import type { LiteMessage, LiteRoom, LiteMember } from '@/matrix-lite/types';
import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import type { MatrixMessage } from './MatrixTimelineService';

/**
 * Simplified Matrix ViewModel backed by mock data.
 * Provides the same public API as the real MatrixViewModel but
 * operates entirely in-memory.
 */
export class MatrixLiteViewModel implements IModuleViewModel {
  private static instance: MatrixLiteViewModel;

  private client: MatrixLiteClient = createMockClient();
  private timeline: Writable<IMatrixTimelineItem[]> = writable([]);
  private rooms: LiteRoom[] = [];
  private currentUser = '@alice:example.org';
  private repoListeners = new Set<(ev: any, room: any) => void>();

  private constructor() {}

  public static getInstance(): MatrixLiteViewModel {
    if (!MatrixLiteViewModel.instance) {
      MatrixLiteViewModel.instance = new MatrixLiteViewModel();
    }
    return MatrixLiteViewModel.instance;
  }

  async initialize(): Promise<void> {
    console.warn('[compat-mock] MatrixLiteViewModel.initialize()');
    this.rooms = await this.client.listRooms();
    if (this.rooms.length > 0) {
      const msgs = await this.client.getRoomMessages(this.rooms[0].id);
      this.timeline.set(msgs.map(this.toTimelineItem));
    }
  }

  private toTimelineItem = (msg: LiteMessage): IMatrixTimelineItem => {
    return new MatrixTimelineItem({
      id: msg.id,
      title: this.rooms.find((r) => r.id === msg.roomId)?.name || 'Room',
      description: msg.content,
      timestamp: msg.timestamp,
      sender: msg.sender,
    });
  };

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
    return true;
  }

  getCurrentUserId(): string {
    return this.currentUser;
  }

  getCurrentUserDisplayName(): string {
    return 'Alice';
  }

  async getRoomMessages(roomId: string, _beforeTS: number | null, _limit = 20): Promise<{ messages: MatrixMessage[]; nextBatch: number | null }> {
    const msgs = await this.client.getRoomMessages(roomId);
    return {
      messages: msgs.map((m) => ({
        id: m.id,
        sender: m.sender,
        senderDisplayName: m.sender,
        description: m.content,
        timestamp: m.timestamp,
        isSelf: m.sender === this.currentUser,
      })),
      nextBatch: null,
    };
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

  clearMediaCache(): void {
    // no-op for mock
  }

  async sendMessage(roomId: string, messageContent: string): Promise<void> {
    await this.client.sendMessage(roomId, messageContent);
    if (this.rooms[0]?.id === roomId) {
      const msgs = await this.client.getRoomMessages(roomId);
      this.timeline.set(msgs.map(this.toTimelineItem));
    }
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
    console.warn('[compat-mock] restoreFromRecoveryKey() called');
  }
}
