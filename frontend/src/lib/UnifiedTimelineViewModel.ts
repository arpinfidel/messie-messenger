import { MatrixViewModel } from './matrix/MatrixViewModel';
import type { IMatrixTimelineItem } from './matrix/MatrixTimelineItem';
import { writable, type Writable, get } from 'svelte/store';

export interface TimelineItem {
  id: string;
  type: string;
  title: string;
  description?: string;
  timestamp: number;
}

export class UnifiedTimelineViewModel {
  private matrixViewModel: MatrixViewModel;
  constructor() {
    this.matrixViewModel = MatrixViewModel.getInstance();
    // No longer managing its own writable store, directly uses MatrixViewModel's
    this.initializeMatrixClient();
    console.log('UnifiedTimelineViewModel: Initialized, relying on MatrixViewModel for timeline store.');
  }

  private initializeMatrixClient() {
    // This method is primarily for logging or future module-specific initialization
    if (this.matrixViewModel.isLoggedIn()) {
      console.log("[UnifiedTimelineViewModel] Matrix client logged in.");
    } else {
      console.warn("[UnifiedTimelineViewModel] Matrix client not logged in.");
    }
  }

  public getMatrixTimelineStore(): Writable<IMatrixTimelineItem[]> {
    return this.matrixViewModel.getTimelineItems();
  }

  // Method to aggregate items from different modules
  public aggregateItems(): TimelineItem[] {
    const matrixItems = get(this.getMatrixTimelineStore());
    // In the future, aggregate items from other modules here
    console.log('UnifiedTimelineViewModel: Aggregated matrixItems:', matrixItems);
    return [...matrixItems];
  }

  // Method to sort timeline items
  public sortItems(items: TimelineItem[]): TimelineItem[] {
    return items.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
  }
  public getSortedTimelineItems(): TimelineItem[] {
    const aggregatedItems = this.aggregateItems();
    const sortedItems = this.sortItems(aggregatedItems);
    console.log('UnifiedTimelineViewModel: Sorted items:', sortedItems);
    return sortedItems;
  }
}