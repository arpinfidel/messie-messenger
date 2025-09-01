import * as matrixSdk from 'matrix-js-sdk';
import { MatrixDataLayer } from './MatrixDataLayer';

/**
 * Cache-first message pipeline. Only two methods hit the Matrix SDK
 * directly: handleSync for incoming events and loadMoreMessages for
 * user-driven pagination. All messages are persisted to IndexedDB
 * before being exposed to the rest of the app.
 */
export class MatrixMessageCache {
  constructor(
    private readonly layer: MatrixDataLayer,
    private readonly ctx: { getClient: () => matrixSdk.MatrixClient | null }
  ) {}

  private get client() {
    return this.ctx.getClient();
  }

  /**
   * Ingest a batch of sync events for a room and persist them to cache.
   * Events are written to IndexedDB via the data layer before returning.
   */
  async handleSync(roomId: string, events: matrixSdk.MatrixEvent[]): Promise<void> {
    const c = this.client;
    if (!c) return;
    const room = c.getRoom(roomId);
    if (!room) return;
    for (const ev of events) {
      await this.layer.ingestLiveEvent(ev, room);
    }
  }

  /**
   * Load older messages from the Matrix homeserver and store them in the
   * cache. Consumers should query the cache afterwards to retrieve the
   * newly stored messages.
   */
  async loadMoreMessages(roomId: string, limit = 50): Promise<void> {
    await this.layer.loadOlder(roomId, limit);
  }
}

