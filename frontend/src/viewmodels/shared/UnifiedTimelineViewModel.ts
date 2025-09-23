import { derived, writable, readable, type Readable } from 'svelte/store';
import type { TimelineItem } from '@/models/shared/TimelineItem';
import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import { TodoViewModel, type CreateTodoListState } from '@/viewmodels/todo/TodoViewModel';
import { MatrixViewModel } from '@/viewmodels/matrix/MatrixViewModel';
import { EmailViewModel } from '@/viewmodels/email/EmailViewModel';
import {
  DEFAULT_TIMELINE_SOURCE_FILTER,
  TIMELINE_SOURCE_FILTERS,
} from '@/config/timelineSources';

export class UnifiedTimelineViewModel {
  private modules: IModuleViewModel[] = [];
  private todoViewModel: TodoViewModel;
  private _loadingModuleNames = writable<string[]>([]);
  private searchTerm = writable<string>('');
  private sourceFilter = writable<string>(DEFAULT_TIMELINE_SOURCE_FILTER);
  public loadingModuleNames: Readable<string[]> = readable([], (set: (value: string[]) => void) =>
    this._loadingModuleNames.subscribe(set)
  );
  public isLoading: Readable<boolean> = derived(
    this._loadingModuleNames,
    ($names) => $names.length > 0
  );

  constructor() {
    this.todoViewModel = TodoViewModel.getInstance();
    this.modules = [
      MatrixViewModel.getInstance(),
      EmailViewModel.getInstance(),
      this.todoViewModel,
    ];
    this.initializeModules();
    console.log('UnifiedTimelineViewModel: Initialized');
  }

  private async initializeModules(): Promise<void> {
    const initializationPromises: Promise<void>[] = [];

    for (const module of this.modules) {
      const moduleName = module.getModuleName();
      this._loadingModuleNames.update((names) => [...names, moduleName]); // Add module to loading list

      const promise = module
        .initialize()
        .then(() => {
          this._loadingModuleNames.update((names) => names.filter((name) => name !== moduleName)); // Remove module from loading list
          // console.log(`[UnifiedTimelineViewModel] Module '${moduleName}' initialized.`);
        })
        .catch((error) => {
          this._loadingModuleNames.update((names) => names.filter((name) => name !== moduleName));
          console.error(
            `[UnifiedTimelineViewModel] Error initializing module '${moduleName}':`,
            error
          );
          // Potentially handle error state for individual modules
        });
      initializationPromises.push(promise);
    }

    // We don't need to await Promise.all(initializationPromises) here if we want optimistic updates.
    // The isLoading derived store will handle the overall loading state.
    // However, the constructor might still need to await something if subsequent logic depends on all modules *starting* initialization.
    // For now, let's just let the promises run in the background.
  }

  /**
   * Reactive aggregate across all modules.
   */
  public getAggregatedTimelineStore(): Readable<TimelineItem[]> {
    const moduleTimelineStores = this.modules.map((module) => module.getTimelineItems());

    return derived(moduleTimelineStores, (stores) => {
      const allItems: TimelineItem[] = [];
      stores.forEach((store) => {
        // Assuming getTimelineItems returns Writable<TimelineItem[]>
        // We need to get the current value from the store.
        // For derived stores, the values are passed directly.
        // For writable stores, we need to ensure they are unwrapped if necessary.
        // In this context, 'stores' will be an array of the current values from the moduleTimelineStores.
        allItems.push(...store);
      });
      // Merge without sorting; keep this a pure aggregation layer.
      return allItems;
    });
  }

  /**
   * Sorted view of the aggregated store (descending by timestamp).
   */
  public getSortedTimelineStore(): Readable<TimelineItem[]> {
    const aggregated = this.getAggregatedTimelineStore();
    return derived([aggregated, this.searchTerm, this.sourceFilter], ([$items, $search, $filter]) => {
      const normalizedSearch = ($search || '').trim().toLowerCase();
      const selectedOption =
        TIMELINE_SOURCE_FILTERS.find((option) => option.id === $filter) ||
        TIMELINE_SOURCE_FILTERS.find((option) => option.id === DEFAULT_TIMELINE_SOURCE_FILTER) ||
        TIMELINE_SOURCE_FILTERS[0];
      const allowedSources = (selectedOption?.sources ?? []).map((s) => s.toLowerCase());

      const filtered = $items.filter((item) => {
        const itemSource = (item.source ?? item.type ?? '').toLowerCase();
        const matchesSource =
          allowedSources.length === 0 || allowedSources.includes(itemSource);
        const matchesSearch =
          normalizedSearch.length === 0
            ? true
            : (item.title || '').toLowerCase().includes(normalizedSearch);
        return matchesSource && matchesSearch;
      });

      return filtered.sort((a, b) => b.timestamp - a.timestamp);
    });
  }

  public getSearchTermStore(): Readable<string> {
    return this.searchTerm;
  }

  public setSearchTerm(term: string): void {
    this.searchTerm.set(term ?? '');
  }

  public getSourceFilterStore(): Readable<string> {
    return this.sourceFilter;
  }

  public setSourceFilter(filterId: string): void {
    const nextFilter = TIMELINE_SOURCE_FILTERS.some((option) => option.id === filterId)
      ? filterId
      : DEFAULT_TIMELINE_SOURCE_FILTER;
    this.sourceFilter.set(nextFilter);
  }

  public getTodoCreationState(): Readable<CreateTodoListState> {
    return this.todoViewModel.getCreateTodoListState();
  }

  public async createTodoList(payload: { title: string; description?: string }): Promise<void> {
    await this.todoViewModel.createTodoList(payload);
  }

  public resetTodoCreationState(): void {
    this.todoViewModel.resetCreateTodoListState();
  }
}
