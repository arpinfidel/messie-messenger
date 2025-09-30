import * as matrixSdk from 'matrix-js-sdk';
import {
  SlidingSync,
  SlidingSyncEvent,
  SlidingSyncState,
  type MSC3575List,
  type MSC3575RoomSubscription,
} from 'matrix-js-sdk/lib/sliding-sync';
import type { MatrixDataLayer } from './MatrixDataLayer';

type TimerHandle = ReturnType<typeof setInterval> | null;

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
  private readonly subscriptionRefreshMs: number;

  private slidingSync: SlidingSync | null = null;
  private slidingSyncTask: Promise<void> | null = null;
  private joinedRooms = new Set<string>();
  private desiredSubscriptions = new Set<string>();
  private lastHighPriority = new Set<string>();
  private lowPriorityCursor = 0;
  private hasHighPrioritySubscription = false;

  private readyPromise: Promise<void>;
  private readyResolver: (() => void) | null = null;
  private readyResolved = false;

  private rotationTimer: TimerHandle = null;
  private joinedRefreshTimer: TimerHandle = null;

  constructor(opts: SlidingSyncServiceOptions) {
    this.getClient = opts.getClient;
    this.dataLayer = opts.dataLayer;
    this.pollInterval = Math.max(2000, opts.pollIntervalMs ?? 2000);
    this.highPrioritySelector = opts.highPrioritySelector;
    this.highPriorityTimelineLimit = Math.max(1, opts.highPriorityTimelineLimit ?? 80);
    this.lowPriorityTimelineLimit = Math.max(1, opts.lowPriorityTimelineLimit ?? 3);
    this.lowPriorityBatchSize = Math.max(1, opts.lowPriorityBatchSize ?? 120);
    this.subscriptionRefreshMs = Math.max(60000, this.pollInterval * 20);
    this.readyPromise = this.createReadyPromise();
  }

  private createReadyPromise(): Promise<void> {
    return new Promise<void>((resolve) => {
      this.readyResolver = resolve;
      this.readyResolved = false;
    });
  }

  private resolveReady(): void {
    if (this.readyResolved) return;
    this.readyResolved = true;
    this.readyResolver?.();
    this.readyResolver = null;
  }

  public waitUntilReady(): Promise<void> {
    return this.readyPromise;
  }

  public getSlidingSync(): SlidingSync | null {
    return this.slidingSync;
  }

  public async init(): Promise<void> {
    await this.ensureSlidingSync();
    await this.refreshJoinedRooms();
    this.updateSubscriptions(true);
  }

  public start(): void {
    if (!this.slidingSync) {
      void this.init().then(() => this.start());
      return;
    }

    this.startJoinedRefreshTimer();
    this.startRotationTimer();

    if (!this.slidingSyncTask) {
      const task = this.slidingSync
        .start()
        .catch((err) => {
          console.warn('[SlidingSync] start loop failed', err);
        })
        .finally(() => {
          if (this.slidingSyncTask === task) {
            this.slidingSyncTask = null;
          }
        });
      this.slidingSyncTask = task;
    }
  }

  public stop(): void {
    this.stopRotationTimer();
    this.stopJoinedRefreshTimer();
    this.slidingSync?.stop();
    this.slidingSyncTask = null;
    this.desiredSubscriptions.clear();
    this.lastHighPriority.clear();
    this.lowPriorityCursor = 0;
    this.readyPromise = this.createReadyPromise();
  }

  private async ensureSlidingSync(): Promise<void> {
    if (this.slidingSync) return;
    const client = this.getClient();
    if (!client) {
      throw new Error('Matrix client not available for sliding sync');
    }

    const listParams: MSC3575List = {
      ranges: [[0, this.lowPriorityBatchSize - 1]],
      timeline_limit: this.lowPriorityTimelineLimit,
      required_state: this.requiredStateTypes(),
      slow_get_all_rooms: true,
    };

    const lists = new Map<string, MSC3575List>();
    lists.set('all', listParams);

    const defaultSubscription: MSC3575RoomSubscription = {
      timeline_limit: this.lowPriorityTimelineLimit,
      required_state: this.requiredStateTypes(),
    };

    const slidingSync = new SlidingSync(
      client.baseUrl ?? '',
      lists,
      defaultSubscription,
      client,
      this.pollInterval
    );

    slidingSync.on(SlidingSyncEvent.RoomData, async (roomId, roomData) => {
      try {
        await this.dataLayer.applySlidingSyncRoom(roomId, roomData, {
          isInitial: !this.readyResolved,
        });
      } catch (err) {
        console.warn('[SlidingSync] failed to apply room data', err);
      }
    });

    slidingSync.on(SlidingSyncEvent.Lifecycle, (state, _resp, err) => {
      if (err) {
        console.warn('[SlidingSync] lifecycle error', err);
      }
      if (state === SlidingSyncState.Complete) {
        this.resolveReady();
      }
    });

    slidingSync.addCustomSubscription('high_priority', {
      timeline_limit: this.highPriorityTimelineLimit,
      required_state: this.requiredStateTypes(),
    });
    this.hasHighPrioritySubscription = true;

    this.slidingSync = slidingSync;
  }

  private async refreshJoinedRooms(): Promise<void> {
    const client = this.getClient();
    if (!client) return;
    try {
      const resp = await client.getJoinedRooms();
      if (Array.isArray(resp?.joined_rooms)) {
        this.joinedRooms = new Set(resp.joined_rooms);
      }
    } catch (err) {
      console.warn('[SlidingSync] Failed to fetch joined rooms', err);
    }
  }

  private startRotationTimer(): void {
    if (this.rotationTimer != null) return;
    this.rotationTimer = setInterval(() => {
      this.updateSubscriptions();
    }, this.pollInterval);
  }

  private stopRotationTimer(): void {
    if (this.rotationTimer != null) {
      clearInterval(this.rotationTimer);
      this.rotationTimer = null;
    }
  }

  private startJoinedRefreshTimer(): void {
    if (this.joinedRefreshTimer != null) return;
    this.joinedRefreshTimer = setInterval(() => {
      void this.refreshJoinedRooms().then(() => this.updateSubscriptions());
    }, this.subscriptionRefreshMs);
  }

  private stopJoinedRefreshTimer(): void {
    if (this.joinedRefreshTimer != null) {
      clearInterval(this.joinedRefreshTimer);
      this.joinedRefreshTimer = null;
    }
  }

  private updateSubscriptions(force = false): void {
    if (!this.slidingSync) return;
    if (!this.joinedRooms.size) {
      this.desiredSubscriptions.clear();
      return;
    }

    const highPriorityInput = this.highPrioritySelector?.() ?? [];
    const highPriority = new Set<string>();
    for (const roomId of highPriorityInput) {
      if (this.joinedRooms.has(roomId)) {
        highPriority.add(roomId);
      }
    }
    this.lastHighPriority = highPriority;

    const joinedList = Array.from(this.joinedRooms);
    const lowPriorityRooms = joinedList.filter((roomId) => !highPriority.has(roomId));

    const desired = new Set<string>(highPriority);
    if (lowPriorityRooms.length) {
      const batchSize = Math.min(this.lowPriorityBatchSize, lowPriorityRooms.length);
      for (let i = 0; i < batchSize; i += 1) {
        const idx = (this.lowPriorityCursor + i) % lowPriorityRooms.length;
        desired.add(lowPriorityRooms[idx]);
      }
      this.lowPriorityCursor = (this.lowPriorityCursor + batchSize) % lowPriorityRooms.length;
    }

    if (!desired.size && joinedList.length) {
      desired.add(joinedList[0]);
    }

    if (!force && this.setsEqual(desired, this.desiredSubscriptions)) {
      return;
    }
    this.desiredSubscriptions = desired;

    if (this.hasHighPrioritySubscription) {
      for (const roomId of desired) {
        if (highPriority.has(roomId)) {
          this.slidingSync.useCustomSubscription(roomId, 'high_priority');
        } else {
          this.slidingSync.useCustomSubscription(roomId, 'default');
        }
      }
    }

    try {
      this.slidingSync.modifyRoomSubscriptions(new Set(desired));
    } catch (err) {
      console.warn('[SlidingSync] failed to update subscriptions', err);
    }
  }

  private setsEqual(a: Set<string>, b: Set<string>): boolean {
    if (a.size !== b.size) return false;
    for (const value of a) {
      if (!b.has(value)) return false;
    }
    return true;
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
}
