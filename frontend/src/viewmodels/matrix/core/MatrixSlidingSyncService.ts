import * as matrixSdk from 'matrix-js-sdk';
import type {
  MSC3575List,
  MSC3575RoomData,
  MSC3575RoomSubscription,
} from 'matrix-js-sdk/lib/sliding-sync';
import { SlidingSync, SlidingSyncEvent, SlidingSyncState } from 'matrix-js-sdk/lib/sliding-sync';

import type { MatrixDataLayer } from './MatrixDataLayer';

interface SlidingSyncServiceOptions {
  getClient: () => matrixSdk.MatrixClient | null;
  dataLayer: MatrixDataLayer;
  pollIntervalMs?: number;
  highPrioritySelector?: () => string[];
  highPriorityTimelineLimit?: number;
  lowPriorityTimelineLimit?: number;
  lowPriorityBatchSize?: number;
  requestTimeoutMs?: number;
}

export class MatrixSlidingSyncService {
  private readonly getClient: () => matrixSdk.MatrixClient | null;
  private readonly dataLayer: MatrixDataLayer;
  private readonly requestTimeout: number;
  private readonly highPrioritySelector?: () => string[];
  private readonly highPriorityTimelineLimit: number;
  private readonly lowPriorityTimelineLimit: number;
  private readonly lowPriorityBatchSize: number;

  private joinedRooms: string[] = [];
  private lastJoinedRefresh = 0;
  private readonly joinedRefreshInterval = 60_000;

  private slidingSync: SlidingSync | null = null;
  private readyResolver: (() => void) | null = null;
  private readyPromise: Promise<void>;
  private initialSnapshotCompleted = false;

  constructor(opts: SlidingSyncServiceOptions) {
    this.getClient = opts.getClient;
    this.dataLayer = opts.dataLayer;
    const pollMs = Math.max(1_000, opts.pollIntervalMs ?? 2_000);
    this.requestTimeout = Math.max(5_000, opts.requestTimeoutMs ?? Math.max(pollMs + 2_000, 5_000));
    this.highPrioritySelector = opts.highPrioritySelector;
    this.highPriorityTimelineLimit = Math.max(1, opts.highPriorityTimelineLimit ?? 60);
    this.lowPriorityTimelineLimit = Math.max(1, opts.lowPriorityTimelineLimit ?? 5);
    this.lowPriorityBatchSize = Math.max(1, opts.lowPriorityBatchSize ?? 120);
    this.readyPromise = this.createReadyPromise();
  }

  async init(): Promise<void> {
    this.resetReadyPromise();
    this.initialSnapshotCompleted = false;
    await this.refreshJoinedRooms();
    this.ensureSlidingSync();
  }

  start(): void {
    void this.updateSubscriptions(true);
  }

  stop(): void {
    if (this.slidingSync) {
      this.slidingSync.modifyRoomSubscriptions(new Set());
      this.slidingSync.stop();
    }
  }

  async refreshJoinedRooms(): Promise<void> {
    const now = Date.now();
    if (now - this.lastJoinedRefresh < this.joinedRefreshInterval) {
      return;
    }
    const client = this.getClient();
    if (!client) return;
    try {
      const resp = await client.getJoinedRooms();
      if (Array.isArray(resp?.joined_rooms)) {
        this.joinedRooms = resp.joined_rooms.slice();
        this.lastJoinedRefresh = now;
      }
    } catch (err) {
      console.warn('[SlidingSync] Failed to fetch joined rooms', err);
    }
  }

  waitUntilReady(): Promise<void> {
    return this.readyPromise;
  }

  getSlidingSync(): SlidingSync | null {
    return this.slidingSync;
  }

  private resolveReady(): void {
    if (!this.readyResolver) return;
    this.readyResolver();
    this.readyResolver = null;
  }

  private createReadyPromise(): Promise<void> {
    return new Promise<void>((resolve) => {
      this.readyResolver = resolve;
    });
  }

  private resetReadyPromise(): void {
    this.readyPromise = this.createReadyPromise();
  }

  private ensureSlidingSync(): SlidingSync | null {
    if (this.slidingSync) {
      return this.slidingSync;
    }
    const client = this.getClient();
    if (!client) {
      return null;
    }

    const defaultSubscription: MSC3575RoomSubscription = {
      required_state: this.requiredStateTypes(),
      timeline_limit: this.lowPriorityTimelineLimit,
    };

    const lists = new Map<string, MSC3575List>();
    const baseUrl = client.baseUrl || '';
    const sliding = new SlidingSync(baseUrl, lists, defaultSubscription, client, this.requestTimeout);

    sliding.addCustomSubscription('hp', {
      ...defaultSubscription,
      timeline_limit: this.highPriorityTimelineLimit,
    });
    sliding.addCustomSubscription('lp', defaultSubscription);

    sliding.on(SlidingSyncEvent.RoomData, async (roomId, roomData) => {
      await this.handleRoomData(roomId, roomData);
    });

    sliding.on(SlidingSyncEvent.Lifecycle, (state) => {
      if (state === SlidingSyncState.Complete && !this.initialSnapshotCompleted) {
        this.initialSnapshotCompleted = true;
        this.resolveReady();
      }
      if (state === SlidingSyncState.Complete) {
        void this.updateSubscriptions();
      }
    });

    this.slidingSync = sliding;
    return sliding;
  }

  private async handleRoomData(roomId: string, roomData: MSC3575RoomData): Promise<void> {
    await this.dataLayer.applySlidingSyncRoom(roomId, roomData, {
      isInitial: !this.initialSnapshotCompleted,
    });
  }

  private async updateSubscriptions(force = false): Promise<void> {
    await this.refreshJoinedRooms();
    const sliding = this.ensureSlidingSync();
    if (!sliding) return;
    if (!this.joinedRooms.length) return;

    const joinedSet = new Set(this.joinedRooms);
    const highPriorityRooms = this.computeHighPriorityRoomsForSet(joinedSet);
    const desired = await this.computeDesiredSubscriptions(highPriorityRooms, joinedSet);

    // Assign subscription profiles before modifying the global set to ensure
    // we resend correct parameters during the next request.
    for (const roomId of desired) {
      if (highPriorityRooms.has(roomId)) {
        sliding.useCustomSubscription(roomId, 'hp');
      } else {
        sliding.useCustomSubscription(roomId, 'lp');
      }
    }

    // If nothing changed and we weren't forced, skip modifying the subscriptions to avoid churn.
    if (!force) {
      const current = sliding.getRoomSubscriptions();
      if (current.size === desired.size) {
        let identical = true;
        for (const roomId of desired) {
          if (!current.has(roomId)) {
            identical = false;
            break;
          }
        }
        if (identical) {
          return;
        }
      }
    }

    sliding.modifyRoomSubscriptions(desired);
  }

  private computeHighPriorityRooms(): Set<string> {
    return this.computeHighPriorityRoomsForSet(new Set(this.joinedRooms));
  }

  private computeHighPriorityRoomsForSet(joinedSet: Set<string>): Set<string> {
    const hp = new Set<string>();
    const selector = this.highPrioritySelector;
    if (!selector) {
      return hp;
    }
    for (const roomId of selector() ?? []) {
      if (typeof roomId === 'string' && joinedSet.has(roomId)) {
        hp.add(roomId);
      }
    }
    return hp;
  }

  private async computeDesiredSubscriptions(
    highPriorityRooms: Set<string>,
    joinedSet: Set<string>
  ): Promise<Set<string>> {
    const desired = new Set<string>(highPriorityRooms);

    const recentRooms = await this.dataLayer.getRooms();
    const sortedByActivity = [...recentRooms]
      .filter((room) => room && joinedSet.has(room.id))
      .sort((a, b) => (b.latestTimestamp ?? 0) - (a.latestTimestamp ?? 0));

    const maxTotal = Math.max(highPriorityRooms.size + this.lowPriorityBatchSize, this.lowPriorityBatchSize);

    for (const room of sortedByActivity) {
      if (desired.size >= maxTotal) {
        break;
      }
      if (highPriorityRooms.has(room.id)) {
        continue;
      }
      desired.add(room.id);
    }

    if (desired.size < maxTotal) {
      for (const roomId of this.joinedRooms) {
        if (desired.size >= maxTotal) {
          break;
        }
        if (!desired.has(roomId)) {
          desired.add(roomId);
        }
      }
    }

    if (desired.size === 0) {
      for (const roomId of this.joinedRooms.slice(0, this.lowPriorityBatchSize)) {
        desired.add(roomId);
      }
    }

    return desired;
  }

  private requiredStateTypes(): string[][] {
    return [
      ['m.room.name', ''],
      ['m.room.avatar', ''],
      ['m.room.encryption', ''],
      ['com.beeper.room_type', ''],
      ['com.beeper.room_type.v2', ''],
    ];
  }
}
