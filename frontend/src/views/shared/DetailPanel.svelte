<script lang="ts">
  import MatrixDetail from '../matrix/MatrixDetail.svelte';
  import CalendarDetail from '../CalendarDetail.svelte';
  import EmailDetail from '../EmailDetail.svelte';
  import type { TimelineItem } from '../../models/shared/TimelineItem'

  export let selectedItem: TimelineItem | null = null;
</script>

<div class="flex-grow bg-gray-700 p-4 text-white overflow-y-auto">
  {#if selectedItem}
    {#if selectedItem.type === 'matrix'}
      <MatrixDetail item={selectedItem} className="h-full" />
    {:else if selectedItem.type === 'email'}  
      <EmailDetail item={selectedItem} />
    {:else if selectedItem.type === 'calendar' || selectedItem.type === 'Call'}
      <CalendarDetail item={selectedItem} />
    {:else}
      <p>Unknown item type selected.</p>
    {/if}
  {:else}
    <p>No item selected.</p>
  {/if}
</div>