<script lang="ts">
  import type { TimelineItem } from '../models/shared/TimelineItem';

  export let item: TimelineItem;
</script>

<div class="p-4 bg-gray-600 text-white rounded-md">
  <h3 class="text-lg font-bold mb-2">Email Detail View</h3>
  <p><strong>ID:</strong> {item.id}</p>
  <p><strong>Title:</strong> {item.title || 'N/A'}</p>
  <p><strong>Content:</strong> {item.content || item.description || 'N/A'}</p>
  <p><strong>Timestamp:</strong> {new Date(item.timestamp).toLocaleString()}</p>
</div>