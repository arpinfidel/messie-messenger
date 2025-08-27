import { MatrixViewModel } from '../matrix/MatrixViewModel';
import { derived, type Readable } from 'svelte/store';
import type { TimelineItem } from 'models/shared/TimelineItem';

export class UnifiedTimelineViewModel {
  private matrixViewModel: MatrixViewModel;

  constructor() {
    this.matrixViewModel = MatrixViewModel.getInstance();
    this.initializeMatrixClient();
    console.log('UnifiedTimelineViewModel: Initialized');
  }

  private initializeMatrixClient() {
    // This method is primarily for logging or future module-specific initialization
    if (this.matrixViewModel.isLoggedIn()) {
      console.log('[UnifiedTimelineViewModel] Matrix client logged in.');
    } else {
      console.warn('[UnifiedTimelineViewModel] Matrix client not logged in.');
    }
  }

  /**
   * Reactive aggregate across all modules (currently just Matrix).
   * Add more module stores to the array as you integrate them.
   */
  public getAggregatedTimelineStore(): Readable<TimelineItem[]> {
    const matrixStore = this.matrixViewModel.getTimelineItems(); // Writable<TimelineItem[]>

    // If you later add more modules, include them in the array below.
    return derived([matrixStore], ([$matrix]) => {
      // Merge without sorting; keep this a pure aggregation layer.
      return [...$matrix];
    });
  }

  /**
   * Sorted view of the aggregated store (descending by timestamp).
   */
  public getSortedTimelineStore(): Readable<TimelineItem[]> {
    const aggregated = this.getAggregatedTimelineStore();
    return derived(aggregated, ($items) => {
      const sorted = $items.slice().sort((a, b) => b.timestamp - a.timestamp);
      console.log('UnifiedTimelineViewModel: Derived sorted count:', sorted.length);
      return sorted;
    });
  }
}
