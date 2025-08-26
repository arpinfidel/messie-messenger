<script lang="ts">
  import ChatDetail from './ChatDetail.svelte';
  import EmailDetail from './EmailDetail.svelte';
  import CalendarDetail from './CalendarDetail.svelte';

  interface TimelineItem {
    id: number | string;
    type: 'Message' | 'Call' | 'email' | 'calendar' | 'chat';
    title?: string;
    description?: string;
    content?: string;
    timestamp: string;
  }

  export let selectedItem: TimelineItem | null = null;
</script>

<div class="flex-grow bg-gray-700 p-4 text-white overflow-y-auto">
  {#if selectedItem}
    {#if selectedItem.type === 'chat' || selectedItem.type === 'Message'}
      <ChatDetail item={selectedItem} />
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