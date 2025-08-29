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
  <h2 class="truncate text-xl font-semibold">{item.title}</h2>
  <p class="text-sm text-gray-600">
    {new Date(item.timestamp).toLocaleString()}
  </p>
  <p class="mt-2 truncate text-gray-700">{item.description}</p>
  <span
    class="mt-2 inline-block rounded-full bg-blue-500 px-3 py-1 text-xs font-semibold text-white"
    >{item.type}</span
  >
</div>