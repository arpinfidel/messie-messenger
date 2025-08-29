import { ClientEvent, RoomEvent } from 'matrix-js-sdk';
import type { MatrixTimelineService } from '@/viewmodels/matrix/MatrixTimelineService';
import type * as matrixSdk from 'matrix-js-sdk';
import type { OutgoingMessageQueue } from './OutgoingMessageQueue';

export type HydrationGetter = () => 'idle' | 'syncing' | 'decrypting' | 'ready';

export class MatrixEventBinder {
  private bound = false;

  constructor(
    private getClient: () => matrixSdk.MatrixClient | null,
    private getHydration: HydrationGetter,
    private timelineSvc: MatrixTimelineService,
    private queue: OutgoingMessageQueue
  ) {}

  bind() {
    const client = this.getClient();
    if (!client || this.bound) return;
    this.bound = true;

    client.on(RoomEvent.Timeline, async (event, room, toStartOfTimeline, removed) => {
      if (toStartOfTimeline || removed || !room) return;

      if (this.getHydration() !== 'ready') {
        this.timelineSvc.bufferLiveEvent(event, room);
        return;
      }
      try {
        await this.timelineSvc.pushTimelineItemFromEvent(event, room);
      } catch (e) {
        console.warn('[RoomEvent.Timeline] push failed:', e);
      }
    });

    client.on(ClientEvent.Sync, async (state) => {
      if (state === 'PREPARED') {
        this.timelineSvc.scheduleTimelineRefresh();
        this.queue.process();
      }
    });

    client.on(ClientEvent.Room, async () => {
      this.timelineSvc.scheduleTimelineRefresh(500);
    });
  }
}
