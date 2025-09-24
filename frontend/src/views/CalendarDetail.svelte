<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { X } from 'lucide-svelte';
  import type { TimelineItem } from '../models/shared/TimelineItem';

  export let item: TimelineItem;
  const dispatch = createEventDispatcher();

  function closePanel() {
    dispatch('close');
  }
</script>

<div class="rounded-md bg-gray-600 p-4 text-white">
  <div class="mb-4 flex items-start justify-between gap-3">
    <h3 class="text-lg font-bold">Calendar Event Detail View</h3>
    <button
      class="shrink-0 rounded-lg p-2 text-gray-200 transition-colors hover:bg-gray-500 hover:text-white"
      on:click={closePanel}
      aria-label="Close calendar details"
    >
      <X class="h-5 w-5" aria-hidden="true" />
    </button>
  </div>
  <p><strong>ID:</strong> {item.id}</p>
  <p><strong>Title:</strong> {item.title || 'N/A'}</p>
  <p><strong>Content:</strong> {item.content || item.description || 'N/A'}</p>
  <p><strong>Timestamp:</strong> {new Date(item.timestamp).toLocaleString()}</p>
</div>
