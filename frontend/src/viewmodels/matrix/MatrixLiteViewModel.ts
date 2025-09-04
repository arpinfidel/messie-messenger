import { writable, type Writable } from 'svelte/store';
import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import { MatrixTimelineItem, type IMatrixTimelineItem } from '@/viewmodels/matrix/MatrixTimelineItem';
import type { MatrixMessage } from '@/viewmodels/matrix/MatrixTypes';
import {
  loginWithPassword,
  logout as liteLogout,
  listJoinedRooms,
  getRoomState,
  getMessages as liteGetMessages,
  getRoomMembers as liteGetMembers,
} from '@/matrix-lite/client';

export class MatrixLiteViewModel implements IModuleViewModel {
  private static instance: MatrixLiteViewModel;
  private timelineItems: Writable<IMatrixTimelineItem[]> = writable([]);
  private loggedIn = false;

  private constructor() {}

  static getInstance(): MatrixLiteViewModel {
    if (!MatrixLiteViewModel.instance) {
      MatrixLiteViewModel.instance = new MatrixLiteViewModel();
    }
    return MatrixLiteViewModel.instance;
  }

  getSettingsComponent(): any {
    return null;
  }
  getModuleName(): string {
    return 'MatrixLite';
  }

  isLoggedIn(): boolean {
    return this.loggedIn;
  }

  getTimelineItems(): Writable<IMatrixTimelineItem[]> {
    return this.timelineItems;
  }

  getCurrentUserId(): string {
    return '@mock:example.org';
  }

  getCurrentUserDisplayName(): string {
    return 'Mock User';
  }

  async initialize(): Promise<void> {
    const rooms = await listJoinedRooms();
    const items: IMatrixTimelineItem[] = [];
    for (const id of rooms) {
      const state = await getRoomState(id);
      const nameEvt = state.find((s: any) => s.type === 'm.room.name');
      const name = nameEvt?.content?.name || id;
      items.push(
        new MatrixTimelineItem({
          id,
          type: 'matrix',
          title: name,
          description: '',
          avatarUrl: undefined,
          timestamp: Date.now(),
        })
      );
    }
    this.timelineItems.set(items);
    this.loggedIn = true;
  }

  async login(hsUrl: string, username: string, password: string): Promise<void> {
    await loginWithPassword(username, password);
    await this.initialize();
  }

  async logout(): Promise<void> {
    await liteLogout();
    this.loggedIn = false;
    this.timelineItems.set([]);
  }

  async getRoomMessages(roomId: string, beforeTS: number | null, limit = 20) {
    const res = await liteGetMessages(roomId);
    const messages: MatrixMessage[] = res.chunk.map((e: any) => ({
      id: e.event_id,
      sender: e.sender,
      senderDisplayName: e.sender,
      description: e.content?.body || '',
      timestamp: e.origin_server_ts,
      isSelf: false,
      msgtype: e.content?.msgtype,
    }));
    return { messages, nextBatch: res.nextBatch };
  }

  async getRoomMembers(roomId: string) {
    return liteGetMembers(roomId);
  }

  onRepoEvent() {
    return () => {};
  }

  mapRepoEventsToMessages(events: any[]): Promise<MatrixMessage[]> {
    return Promise.resolve([]);
  }

  clearMediaCache(): void {}

  queryCachedRoomEvents(roomId: string, limit = 50, beforeTs?: number) {
    return Promise.resolve([]);
  }

  verifyCurrentDevice(): Promise<void> {
    return Promise.resolve();
  }

  getOpenIdToken(): Promise<any> {
    return Promise.reject(new Error('not implemented'));
  }
}
