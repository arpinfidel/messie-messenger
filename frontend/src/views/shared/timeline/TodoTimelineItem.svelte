<script lang="ts">
  import type { TimelineItem } from '@/models/shared/TimelineItem';
  import { createEventDispatcher } from 'svelte';

  export let item: TimelineItem;

  const dispatch = createEventDispatcher();

  function selectItem(selectedItem: TimelineItem) {
    dispatch('itemSelected', selectedItem);
  }
</script>

<div
  class="cursor-pointer rounded-lg bg-white p-4 shadow-md hover:bg-gray-50"
  on:click={() => selectItem(item)}
>
  <div class="flex items-center justify-between">
    <h2 class="truncate text-xl font-semibold">{item.title}</h2>
    {#if item.completed}
      <span class="text-sm font-medium text-green-500">Completed</span>
    {:else}
      <span class="text-sm font-medium text-yellow-500">Pending</span>
    {/if}
  </div>
  {#if item.description}
    <p class="mt-2 truncate text-gray-700">{item.description}</p>
  {/if}
  {#if item.dueDate}
    <p class="text-sm text-gray-600">
      Due: {new Date(item.dueDate).toLocaleString()}
    </p>
  {/if}
  <p class="text-sm text-gray-600">
    Created: {new Date(item.timestamp).toLocaleString()}
  </p>
  <span
    class="mt-2 inline-block rounded-full bg-purple-500 px-3 py-1 text-xs font-semibold text-white"
    >{item.type}</span
  >
</div>