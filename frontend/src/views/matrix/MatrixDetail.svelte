<script lang="ts">
  import type { TimelineItem } from 'models/shared/TimelineItem'
  import { MatrixViewModel } from '../../viewmodels/matrix/MatrixViewModel';

  export let item: TimelineItem;

  let messageContent: string = '';

  async function sendMessage() {
    if (!messageContent.trim() || !item.id) {
      alert('Message cannot be empty or room ID is missing.');
      return;
    }

    try {
      const matrixViewModel = MatrixViewModel.getInstance();
      await matrixViewModel.sendMessage(item.id, messageContent);
      messageContent = ''; // Clear input after sending
      console.log(`Message sent to room ${item.id}`);
      // Optionally, trigger a refresh of the timeline in UnifiedTimeline.svelte
      // This would require a more sophisticated state management (e.g., Svelte store)
    } catch (error) {
      console.error('Failed to send message:', error);
      alert('Failed to send message. Check console for details.');
    }
  }
</script>

<div class="p-4 bg-gray-600 text-white rounded-md">
  <h3 class="text-lg font-bold mb-2">Chat Detail View</h3>
  <p><strong>ID:</strong> {item.id}</p>
  <p><strong>Title:</strong> {item.title || 'N/A'}</p>
  <p><strong>Content:</strong> {item.description || 'N/A'}</p>
  <p><strong>Timestamp:</strong> {new Date(item.timestamp).toLocaleString()}</p>

  {#if item.type === 'matrix'}
    <div class="mt-4">
      <h4 class="text-lg font-semibold mb-2">Send Matrix Message</h4>
      <input
        type="text"
        bind:value={messageContent}
        placeholder="Type your message..."
        class="w-full p-2 rounded-md text-gray-900"
        on:keydown={(e) => { if (e.key === 'Enter') sendMessage(); }}
      />
      <button
        on:click={sendMessage}
        class="mt-2 px-4 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600"
      >
        Send
      </button>
    </div>
  {/if}
</div>