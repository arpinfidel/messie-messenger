<script lang="ts">
  import MatrixDetail from '../matrix/MatrixDetail.svelte';
  import CalendarDetail from '../CalendarDetail.svelte';
  import EmailDetail from '../EmailDetail.svelte';
  import TodoDetail from '../todo/TodoDetail.svelte'; // Import TodoDetail
  import type { TimelineItem } from '../../models/shared/TimelineItem';

  export let selectedItem: TimelineItem | null = null;

  function closeDetail() {
    selectedItem = null;
  }
</script>

<div class="flex-grow overflow-y-auto bg-gray-900 text-gray-100">
  {#if selectedItem}
    {#if selectedItem.type === 'matrix'}
      <MatrixDetail item={selectedItem} className="h-full" />
    {:else if selectedItem.type === 'email'}
      <EmailDetail item={selectedItem} />
    {:else if selectedItem.type === 'calendar' || selectedItem.type === 'Call'}
      <CalendarDetail item={selectedItem} />
    {:else if selectedItem.type === 'todo'}
      {#if selectedItem.listId}
        <TodoDetail listId={selectedItem.listId} on:close={closeDetail} />
      {/if}
    {:else}
      <p>Unknown item type selected.</p>
    {/if}
  {:else}
    <div class="flex h-full flex-col items-center justify-center space-y-4">
      <img src="/messie-logo.svg" alt="Messie Logo" class="h-16 w-16 opacity-80" />
      <div class="text-center">
        <p class="text-lg font-medium text-gray-200">No item selected</p>
        <p class="text-sm text-gray-400">Choose something from the timeline to view details.</p>
      </div>
    </div>
  {/if}
</div>
