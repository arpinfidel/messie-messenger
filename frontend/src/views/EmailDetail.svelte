<script lang="ts">
  import type { TimelineItem } from '../models/shared/TimelineItem';

  export let item: TimelineItem;
</script>

<div class="rounded-md bg-gray-600 p-4 text-white">
  <h3 class="mb-2 text-lg font-bold">Email Detail View</h3>
  <p><strong>ID:</strong> {item.id}</p>
  <p><strong>Title:</strong> {item.title || 'N/A'}</p>
  <p><strong>Content:</strong> {item.content || item.description || 'N/A'}</p>
  <p><strong>Timestamp:</strong> {new Date(item.timestamp).toLocaleString()}</p>
</div>
