<script lang="ts">
  import { MatrixViewModel } from '../../../viewmodels/matrix/MatrixViewModel';

  export let title: string = 'Matrix Room';
  export let messageCount: number = 0;
  export let className: string = '';
  export let roomId: string = '';

  const matrixViewModel = MatrixViewModel.getInstance();
  let showInfo = false;
  let members: any[] = [];

  async function openInfo() {
    if (!roomId) return;
    try {
      members = await matrixViewModel.getRoomMembers(roomId);
    } catch (e) {
      console.error('[RoomHeader] failed to load members', e);
      members = [];
    }
    showInfo = true;
  }

  function closeInfo() {
    showInfo = false;
  }
</script>

<div class="room-header {className}">
  <div class="flex items-center space-x-3">
    <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-emerald-500 to-teal-600 shadow-lg">
      <svg class="h-5 w-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
      </svg>
    </div>
    <div>
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white">{title}</h2>
      <p class="text-sm text-gray-500 dark:text-gray-400">{messageCount} messages</p>
    </div>
  </div>
  <div class="flex items-center space-x-2">
    <button
      class="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300"
      on:click={openInfo}
    >
      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    </button>
  </div>
</div>

{#if showInfo}
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
    <div class="max-h-[80vh] w-full max-w-lg overflow-auto rounded-lg bg-white p-4 shadow-lg dark:bg-gray-800">
      <h3 class="mb-2 text-lg font-semibold">Debug Info</h3>
      <p class="mb-2 text-sm">Room ID: {roomId}</p>
      <pre class="max-h-[60vh] overflow-auto rounded bg-gray-100 p-2 text-xs dark:bg-gray-900">{JSON.stringify(members, null, 2)}</pre>
      <button
        class="mt-4 rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600"
        on:click={closeInfo}
      >
        Close
      </button>
    </div>
  </div>
{/if}

<style>
  .room-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.5rem;
    background: var(--color-panel);
    border-bottom: 1px solid var(--color-panel-border);
    position: sticky;
    top: 0;
    z-index: 10;
  }
</style>

