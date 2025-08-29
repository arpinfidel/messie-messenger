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

<div class="flex-grow overflow-y-auto bg-gray-700 p-4 text-white">
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
    <p>No item selected.</p>
  {/if}
</div>
