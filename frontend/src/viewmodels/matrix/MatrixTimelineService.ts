import type * as matrixSdk from 'matrix-js-sdk';
import { EventType, MatrixEvent, Room } from 'matrix-js-sdk';
import { writable, type Writable } from 'svelte/store';

import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixDataStore } from './core/MatrixDataStore';
import { MatrixDataLayer } from './core/MatrixDataLayer';

export interface MatrixMessage {
  id: string;
  sender: string;
  senderDisplayName: string; // Add this line
  description: string;
  timestamp: number;
  isSelf: boolean;
}

export class MatrixTimelineService {
  private _timelineItems: Writable<IMatrixTimelineItem[]> = writable([]);
  private refreshTimer: any = null;
  private listRefreshInFlight = false;
  private pendingLiveEvents: Array<{ ev: MatrixEvent; room: Room }> = [];

  constructor(
    private readonly ctx: {
      getClient: () => matrixSdk.MatrixClient | null;
      isStarted: () => boolean;
      getHydrationState: () => 'idle' | 'syncing' | 'decrypting' | 'ready';
    },
    private readonly store: MatrixDataStore,
    private readonly layer: MatrixDataLayer
  ) {}

  private get client() {
    return this.ctx.getClient();
  }

  getTimelineItemsStore(): Writable<IMatrixTimelineItem[]> {
    return this._timelineItems;
  }

  /** Unified room list with their latest message preview.
   * Compute strictly from our MatrixDataStore instead of querying the SDK.
   */
  async fetchAndSetTimelineItems(): Promise<void> {
    if (!this.ctx.isStarted() || this.ctx.getHydrationState() !== 'ready') return;
    if (this.listRefreshInFlight) return;

    this.listRefreshInFlight = true;
    try {
      const rooms = this.store.getRooms();

      // Ensure at least one event (latest) is present to build previews.
      // Do this via the data layer, not by reading the SDK directly here.
      for (const r of rooms) {
        if (!this.store.getLatestEvent(r.id)) {
          try {
            await this.layer.fetchInitial(r.id, 1);
          } catch {}
        }
      }

      const items = rooms.map((room) => {
        const last = this.store.getLatestEvent(room.id);
        let description = 'No recent messages';
        // Prefer stored latestTimestamp (may be loaded from IndexedDB even if events tail is sparse)
        let timestamp = room.latestTimestamp || 0;
        if (last) {
          const preview = this.repoEventToPreview(last);
          description = preview.description;
          timestamp = last.originServerTs || timestamp || 0;
        }
        return new MatrixTimelineItem({
          id: room.id,
          type: 'matrix',
          title: room.name || room.id,
          description,
          timestamp,
        });
      });

      // Sort items by timestamp in descending order (latest first)
      items.sort((a, b) => b.timestamp - a.timestamp);
      this._timelineItems.set(items);
    } finally {
      this.listRefreshInFlight = false;
    }
  }

  scheduleTimelineRefresh(delay = 200) {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(async () => {
      this.refreshTimer = null;
      if (this.ctx.getHydrationState() !== 'ready' || this.listRefreshInFlight) return;

      this.listRefreshInFlight = true;
      try {
        await this.fetchAndSetTimelineItems();
      } finally {
        this.listRefreshInFlight = false;
      }
    }, delay);
  }

  /** Live pipeline: ingest event into store via data layer, then update preview. */
  async pushTimelineItemFromEvent(ev: MatrixEvent, room: Room) {
    await this.layer.ingestLiveEvent(ev, room);

    const last = this.store.getLatestEvent(room.roomId);
    const fallbackTs =
      this.store.getRooms().find((r) => r.id === room.roomId)?.latestTimestamp || 0;
    const timestamp = last?.originServerTs ?? fallbackTs;
    const id = room.roomId;
    const title = room.name || room.roomId;
    const { description } = last ? this.repoEventToPreview(last) : { description: '' };

    const updated = new MatrixTimelineItem({
      id,
      type: 'matrix',
      title,
      description,
      timestamp,
    });

    this._timelineItems.update((items) => {
      const idx = items.findIndex((it) => it.id === id);
      if (idx === -1) return [updated, ...items];
      const next = items.slice();
      if ((next[idx]?.timestamp ?? 0) <= timestamp) next[idx] = updated;
      return next;
    });
  }

  bufferLiveEvent(ev: MatrixEvent, room: Room) {
    this.pendingLiveEvents.push({ ev, room });
  }

  async flushPendingLiveEvents() {
    if (!this.pendingLiveEvents.length) return;
    for (const { ev, room } of this.pendingLiveEvents) {
      try {
        await this.pushTimelineItemFromEvent(ev, room);
      } catch {}
    }
    this.pendingLiveEvents.length = 0;
  }

  /* ---------------- Room messages API (delegates to repo) ---------------- */

  /** First page: from live timeline (repo.fetchInitial). */
  async getRoomMessages(
    roomId: string,
    fromToken: string | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    if (!fromToken) {
      const { events, toToken } = await this.layer.fetchInitial(roomId, limit);
      const messages = this.mapRepoEventsToMessages(events);
      return { messages, nextBatch: toToken };
    }
    const page = await this.layer.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  async loadOlderMessages(
    roomId: string,
    fromToken?: string | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    // We ignore `fromToken` and use the store's backward token from live timeline.
    const page = await this.layer.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  clearRoomPaginationTokens(roomId: string) {
    this.layer.clearRoom(roomId);
  }

  /* ---------------- Mapping helpers ---------------- */

  private mapRepoEventsToMessages(events: RepoEvent[]): MatrixMessage[] {
    const currentUserId = this.store.getCurrentUserId() ?? '';
    return events
      .filter((re) => re.type === EventType.RoomMessage || re.type === 'm.room.encrypted')
      .map((re) => {
        const { description } = this.repoEventToPreview(re);
        const isSelf = re.sender === currentUserId;
        const senderDisplayName = re.sender; // Keep data-layer-only: avoid SDK lookup here
        return {
          id: re.eventId || `${Date.now()}-${Math.random()}`,
          sender: re.sender || 'unknown sender',
          senderDisplayName, // Assign display name
          description,
          timestamp: re.originServerTs || 0,
          isSelf,
        };
      });
  }

  /** Create a human preview from RepoEvent content (works for decrypted encrypted). */
  private repoEventToPreview(re: RepoEvent): { description: string } {
    const c = re.content ?? {};
    // Plain text message
    if (typeof c.body === 'string') return { description: c.body };

    // Reaction
    const relates = c['m.relates_to'];
    if (relates?.rel_type === 'm.annotation' && c.key) {
      return { description: `${re.sender} reacted with ${c.key}` };
    }

    // Reply/reference (you can enrich this if you want)
    if (relates?.rel_type === 'm.reference') {
      return { description: 'Replied to a message' };
    }

    // Encrypted (not decrypted or unknown shape)
    return { description: 'This message could not be decrypted.' };
  }
}
