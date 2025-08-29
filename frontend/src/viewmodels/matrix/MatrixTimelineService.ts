import type * as matrixSdk from 'matrix-js-sdk';
import { ClientEvent, EventTimeline, EventType, MatrixEvent, Room } from 'matrix-js-sdk';
import { writable, type Writable } from 'svelte/store';

import type { IModuleViewModel } from '../shared/IModuleViewModel';
import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import { RoomPreviewCache } from './RoomPreviewCache';
import type { RepoEvent, TimelineRepository } from './core/TimelineRepository';

export interface MatrixMessage {
  id: string;
  sender: string;
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
    private readonly repo: TimelineRepository // ← inject the repo
  ) {
    // Subscribe to timeline items and update cache
    this._timelineItems.subscribe((items) => {
      if (this.ctx.getHydrationState() !== 'ready') return;
      if (!items.length) return;
      // Save to localStorage cache
      const cache = new RoomPreviewCache();
      const previews = items.map((it) => ({
        id: it.id,
        title: it.title,
        description: it.description || '', // Ensure description is always a string
        timestamp: it.timestamp,
      }));
      // Ensure items are sorted by timestamp (latest first) before saving
      // Also, only store the latest 100 items to avoid bloating the cache
      previews.sort((a, b) => b.timestamp - a.timestamp).slice(0, 100);
      cache.save(previews);
    });
  }

  private get client() {
    return this.ctx.getClient();
  }

  getTimelineItemsStore(): Writable<IMatrixTimelineItem[]> {
    return this._timelineItems;
  }

  /** Unified room list with their latest message preview. */
  async fetchAndSetTimelineItems(): Promise<void> {
    if (!this.client || !this.ctx.isStarted() || this.ctx.getHydrationState() !== 'ready') return;
    if (this.listRefreshInFlight) return;

    this.listRefreshInFlight = true;
    try {
      const rooms = this.client.getRooms() ?? [];

      const items = await Promise.all(
        rooms.map(async (room) => {
          const live = room.getLiveTimeline().getEvents();
          // Prefer the last real message (plaintext or encrypted-with-clear)
          const last = [...live]
            .reverse()
            .find(
              (e) => e.getType() === EventType.RoomMessage || e.getType() === 'm.room.encrypted'
            );

          let description = 'No recent messages';
          let timestamp = 0;

          if (last) {
            const re = await this.repo.toRepoEvent(last);
            if (re) {
              const preview = this.repoEventToPreview(re);
              description = preview.description;
              timestamp = re.originServerTs || 0;
            }
          }

          return new MatrixTimelineItem({
            id: room.roomId,
            type: 'matrix',
            title: room.name || room.roomId,
            description,
            timestamp,
          });
        })
      );

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

  /** Live pipeline uses the repo for normalization (and decryption). */
  async pushTimelineItemFromEvent(ev: MatrixEvent, room: Room) {
    if (!this.client) return;

    const re = await this.repo.toRepoEvent(ev);
    if (!re) return;

    const timestamp = re.originServerTs || Date.now();
    const id = room.roomId;
    const title = room.name || room.roomId;
    const { description } = this.repoEventToPreview(re);

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
    if (!this.client) throw new Error('Client not initialized');

    if (!fromToken) {
      const { events, toToken } = await this.repo.fetchInitial(roomId, limit);
      const messages = this.mapRepoEventsToMessages(events);
      return { messages, nextBatch: toToken };
    }

    // Fallback to older (backward) page
    const page = await this.repo.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  async loadOlderMessages(
    roomId: string,
    fromToken?: string | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    // We ignore `fromToken` and use the repo's internal backward token from live timeline.
    const page = await this.repo.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  clearRoomPaginationTokens(roomId: string) {
    this.repo.clearRoomState(roomId);
  }

  /* ---------------- Mapping helpers ---------------- */

  private mapRepoEventsToMessages(events: RepoEvent[]): MatrixMessage[] {
    const currentUserId = this.client?.getUserId() ?? '';
    return events
      .filter((re) => re.type === EventType.RoomMessage || re.type === 'm.room.encrypted')
      .map((re) => {
        const { description } = this.repoEventToPreview(re);
        const isSelf = re.sender === currentUserId;
        return {
          id: re.eventId || `${Date.now()}-${Math.random()}`,
          sender: re.sender || 'unknown sender',
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
