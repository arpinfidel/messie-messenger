<script lang="ts">
  export let title: string = 'Matrix Room';
  export let messageCount: number = 0;
  export let className: string = '';
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
    <button class="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300">
      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    </button>
  </div>
</div>

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

