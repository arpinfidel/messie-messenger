<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte';
import { UnifiedTimelineViewModel } from '../../viewmodels/shared/UnifiedTimelineViewModel';
import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel';
import { EmailViewModel } from '../../viewmodels/shared/EmailViewModel';
import type { TimelineItem } from '../../models/shared/TimelineItem'
import LoadingIndicator from './LoadingIndicator.svelte';

  const dispatch = createEventDispatcher();

  export let timelineWidth: number;
  export let timelineLeft: number;

  let items: TimelineItem[] = [];
  let isLoading = true; // Renamed from 'loading' for consistency
  let error: string | null = null;
  let loadingModuleNames: string[] = []; // Declare at top level
  let loadingText = "Loading timeline items..."; // New variable for loading text

  const unifiedTimelineViewModel = new UnifiedTimelineViewModel([
    MatrixViewModel.getInstance(),
    new EmailViewModel()
  ]);

  onMount(async () => {
    unifiedTimelineViewModel.isLoading.subscribe((value) => {
      isLoading = value;
    });

    unifiedTimelineViewModel.loadingModuleNames.subscribe((value) => {
        loadingModuleNames = value;
    });

    try {
      unifiedTimelineViewModel.getSortedTimelineStore().subscribe((value: TimelineItem[]) => {
        items = value;
        console.log(`[UnifiedTimeline] Sorted timeline items updated. Count: ${items.length}`);
      });
    } catch (e: any) {
      error = e.message;
    }
  });

  $: loadingText = loadingModuleNames.length > 0
      ? `Loading: ${loadingModuleNames.join(', ')}`
      : '';

  // Add a reactive statement to log items when they change
  $: {
    console.log(`[UnifiedTimeline] Current items array length: ${items.length}`);
    if (items.length > 0) {
      console.log(`[UnifiedTimeline] First item:`, items[0]);
    }
  }

  function selectItem(item: TimelineItem) {
    dispatch('itemSelected', item);
  }
</script>

<div class="flex-1 p-4 overflow-y-auto">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-3xl font-bold">Mess</h1>
    <button class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded" on:click={() => dispatch('openSettings')}>
      Settings
    </button>
  </div>

  {#if error}
    <p class="text-red-500">Error: {error}</p>
  {:else if items.length === 0 && !isLoading}
    <!-- Only show "No items" if no items AND nothing is loading -->
    <p>No timeline items to display.</p>
  {:else}
    <div class="space-y-4">
      {#each items as item (item.id)}
        <div
          class="bg-white p-4 rounded-lg shadow-md cursor-pointer hover:bg-gray-50"
          on:click={() => selectItem(item)}
        >
          <h2 class="text-xl font-semibold truncate">{item.title}</h2>
          <p class="text-gray-600 text-sm">{new Date(item.timestamp).toLocaleString()}</p>
          <p class="mt-2 text-gray-700 truncate">{item.description}</p>
          <span class="inline-block mt-2 px-3 py-1 text-xs font-semibold text-white bg-blue-500 rounded-full">{item.type}</span>
        </div>
      {/each}
    </div>
  {/if}
</div>

<LoadingIndicator show={isLoading} width={`${timelineWidth + 1}px`} left={`${timelineLeft}px`} text={loadingText} />