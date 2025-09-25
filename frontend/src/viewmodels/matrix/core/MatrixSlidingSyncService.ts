import * as matrixSdk from 'matrix-js-sdk';
import type { IEvent } from 'matrix-js-sdk';
import type { MatrixDataLayer } from './MatrixDataLayer';

interface SlidingSyncRoomEntry {
  name?: string;
  avatar?: string;
  room_type?: string;
  bump_stamp?: number;
  required_state?: IEvent[];
  timeline?: {
    events?: IEvent[];
    limited?: boolean;
  };
  unread_notifications?: {
    notification_count?: number;
    highlight_count?: number;
  };
}

interface SlidingSyncResponse {
  pos?: string;
  rooms?: Record<string, SlidingSyncRoomEntry>;
}

interface SlidingSyncServiceOptions {
  getClient: () => matrixSdk.MatrixClient | null;
  dataLayer: MatrixDataLayer;
  pollIntervalMs?: number;
  highPrioritySelector?: () => string[];
  highPriorityTimelineLimit?: number;
  lowPriorityTimelineLimit?: number;
  lowPriorityBatchSize?: number;
}

export class MatrixSlidingSyncService {
  private readonly getClient: () => matrixSdk.MatrixClient | null;
  private readonly dataLayer: MatrixDataLayer;
  private readonly pollInterval: number;
  private readonly highPrioritySelector?: () => string[];
  private readonly highPriorityTimelineLimit: number;
  private readonly lowPriorityTimelineLimit: number;
  private readonly lowPriorityBatchSize: number;
  private joinedRooms: string[] = [];
  private pos: string | null = null;
  private running = false;
  private readyResolver: (() => void) | null = null;
  private readyPromise: Promise<void>;
  private lowPriorityCursor = 0;
  private initialSnapshotCompleted = false;

  constructor(opts: SlidingSyncServiceOptions) {
    this.getClient = opts.getClient;
    this.dataLayer = opts.dataLayer;
    this.pollInterval = Math.max(1000, opts.pollIntervalMs ?? 2000);
    this.highPrioritySelector = opts.highPrioritySelector;
    this.highPriorityTimelineLimit = Math.max(1, opts.highPriorityTimelineLimit ?? 60);
    this.lowPriorityTimelineLimit = Math.max(1, opts.lowPriorityTimelineLimit ?? 5);
    this.lowPriorityBatchSize = Math.max(1, opts.lowPriorityBatchSize ?? 120);
    this.readyPromise = new Promise<void>((resolve) => {
      this.readyResolver = resolve;
    });
  }

  async init(): Promise<void> {
    await this.refreshJoinedRooms();
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    void this.loop();
  }

  stop(): void {
    this.running = false;
  }

  async refreshJoinedRooms(): Promise<void> {
    const client = this.getClient();
    if (!client) return;
    try {
      const resp = await client.getJoinedRooms();
      if (Array.isArray(resp?.joined_rooms)) {
        this.joinedRooms = resp.joined_rooms.slice();
        this.lowPriorityCursor = 0;
      }
    } catch (err) {
      console.warn('[SlidingSync] Failed to fetch joined rooms', err);
    }
  }

  waitUntilReady(): Promise<void> {
    return this.readyPromise;
  }

  private resolveReady(): void {
    if (!this.readyResolver) return;
    this.readyResolver();
    this.readyResolver = null;
  }

  private async loop(): Promise<void> {
    while (this.running) {
      try {
        await this.tick();
      } catch (err) {
        console.warn('[SlidingSync] tick failed', err);
      }
      if (!this.running) break;
      await this.sleep(this.pollInterval);
    }
  }

  private async tick(): Promise<void> {
    const client = this.getClient();
    if (!client) return;
    if (!this.joinedRooms.length) {
      await this.refreshJoinedRooms();
      if (!this.joinedRooms.length) {
        return;
      }
    }

    const requestBody = this.buildRequest();

    const response = await client.http.authedRequest<SlidingSyncResponse>(
      matrixSdk.Method.Post,
      '/_matrix/client/unstable/org.matrix.simplified_msc3575/sync',
      undefined,
      requestBody
    );

    if (!response) return;

    if (typeof response.pos === 'string') {
      this.pos = response.pos;
    }

    const rooms = response.rooms ?? {};
    const roomIds = Object.keys(rooms);

    for (const roomId of roomIds) {
      const entry = rooms[roomId];
      if (!entry) continue;
      await this.dataLayer.applySlidingSyncRoom(roomId, entry, {
        isInitial: !this.initialSnapshotCompleted,
      });
    }

    if (!this.initialSnapshotCompleted && roomIds.length) {
      this.initialSnapshotCompleted = true;
      this.resolveReady();
    }
  }

  private buildRequest(): any {
    const highPriorityRooms = new Set(this.highPrioritySelector?.() ?? []);

    const lowPriorityRooms = this.joinedRooms.filter((roomId) => !highPriorityRooms.has(roomId));
    const rotatingBoost = new Set<string>();

    if (lowPriorityRooms.length > 0) {
      let consumed = 0;
      while (consumed < this.lowPriorityBatchSize && consumed < lowPriorityRooms.length) {
        const idx = (this.lowPriorityCursor + consumed) % lowPriorityRooms.length;
        rotatingBoost.add(lowPriorityRooms[idx]);
        consumed += 1;
      }
      const advance = consumed > 0 ? consumed : 1;
      this.lowPriorityCursor = (this.lowPriorityCursor + advance) % lowPriorityRooms.length;
    }

    const subs: Record<string, any> = {};
    for (const roomId of this.joinedRooms) {
      const boosted = highPriorityRooms.has(roomId) || rotatingBoost.has(roomId);
      subs[roomId] = {
        timeline_limit: boosted ? this.highPriorityTimelineLimit : this.lowPriorityTimelineLimit,
        required_state: this.requiredStateTypes(),
      };
    }

    return {
      pos: this.pos ?? undefined,
      room_subscriptions: subs,
      lists: {},
      extensions: {
        to_device: { enabled: true },
        e2ee: { enabled: true },
      },
    };
  }

  private requiredStateTypes(): [string, string][] {
    return [
      ['m.room.name', ''],
      ['m.room.avatar', ''],
      ['m.room.encryption', ''],
      ['com.beeper.room_type', ''],
      ['com.beeper.room_type.v2', ''],
    ];
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
