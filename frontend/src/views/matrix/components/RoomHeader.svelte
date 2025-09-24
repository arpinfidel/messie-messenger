<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import PopupMenu from '@/views/shared/PopupMenu.svelte';
  import Modal from '@/views/shared/Modal.svelte';
  import { MatrixViewModel } from '../../../viewmodels/matrix/MatrixViewModel';

  export let title: string = 'Matrix Room';
  export let messageCount: number = 0;
  export let className: string = '';
  export let roomId: string = '';
  export let showClose = false;

  const matrixViewModel = MatrixViewModel.getInstance();
  const dispatch = createEventDispatcher();

  function handleCloseClick() {
    dispatch('close');
  }
  let showInfo = false;
  let members: any[] = [];
  let showMenu = false;
  let menuAnchor: HTMLButtonElement | null = null;
  let isMuted = false;
  let isFetchingMute = false;
  let isUpdatingMute = false;
  let muteStateLoaded = false;
  let lastRoomId: string | null = null;
  let muteRequestToken = 0;

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

  async function loadMuteState(targetRoomId: string): Promise<void> {
    const requestId = ++muteRequestToken;
    muteStateLoaded = false;
    isFetchingMute = true;
    try {
      const muted = await matrixViewModel.refreshRoomMuteState(targetRoomId);
      if (muteRequestToken === requestId && roomId === targetRoomId) {
        isMuted = muted;
        muteStateLoaded = true;
      }
    } catch (err) {
      console.error('[RoomHeader] Failed to load mute state', err);
    } finally {
      if (muteRequestToken === requestId) {
        isFetchingMute = false;
      }
    }
  }

  async function handleMuteToggle() {
    if (!roomId || isUpdatingMute || isFetchingMute) return;
    isUpdatingMute = true;
    try {
      const muted = await matrixViewModel.setRoomMuted(roomId, !isMuted);
      isMuted = muted;
      muteStateLoaded = true;
      showMenu = false;
    } catch (err) {
      console.error('[RoomHeader] Failed to update mute rule', err);
    } finally {
      isUpdatingMute = false;
    }
  }

  function toggleMenu() {
    if (!roomId) return;
    showMenu = !showMenu;
    if (showMenu && !muteStateLoaded && !isFetchingMute) {
      void loadMuteState(roomId);
    }
  }

  $: if (roomId && roomId !== lastRoomId) {
    lastRoomId = roomId;
    showMenu = false;
    void loadMuteState(roomId);
  }

  $: if (!roomId) {
    showMenu = false;
    isMuted = false;
    muteStateLoaded = false;
    isFetchingMute = false;
    isUpdatingMute = false;
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
    {#if showClose}
      <button
        class="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300"
        on:click={handleCloseClick}
        aria-label="Close details"
      >
        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    {/if}
    <button
      class="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300"
      on:click={toggleMenu}
      bind:this={menuAnchor}
      aria-label="Room actions"
    >
      <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path d="M10 4.5a1.25 1.25 0 110-2.5 1.25 1.25 0 010 2.5zm0 6a1.25 1.25 0 110-2.5 1.25 1.25 0 010 2.5zm0 6a1.25 1.25 0 110-2.5 1.25 1.25 0 010 2.5z" />
      </svg>
    </button>
    <button
      class="rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-gray-300"
      on:click={openInfo}
      aria-label="Room information"
    >
      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    </button>
  </div>
</div>

<PopupMenu anchor={menuAnchor} show={showMenu} on:close={() => (showMenu = false)}>
  <button
    class="flex min-w-[12rem] items-center justify-between rounded-md px-3 py-2 text-left text-sm text-gray-700 transition-colors hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:text-gray-200 dark:hover:bg-gray-700"
    on:click={handleMuteToggle}
    disabled={isFetchingMute || isUpdatingMute}
  >
    <span>{isMuted ? 'Unmute room' : 'Mute room'}</span>
    {#if isFetchingMute || isUpdatingMute}
      <span
        class="ml-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-gray-300 border-t-transparent dark:border-gray-600"
      />
    {:else if isMuted}
      <svg class="ml-2 h-4 w-4 text-emerald-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
    {:else if muteStateLoaded}
      <span
        class="ml-2 inline-block h-4 w-4 rounded-full border-2 border-gray-300 dark:border-gray-600"
      />
    {/if}
  </button>
</PopupMenu>

<Modal
  show={showInfo}
  on:close={closeInfo}
  ariaLabelledby="room-debug-info-title"
  containerClass="relative w-full max-w-lg max-h-[80vh] overflow-auto rounded-lg bg-white p-4 shadow-lg outline-none focus:outline-none dark:bg-gray-800"
>
  <h3 id="room-debug-info-title" class="mb-2 text-lg font-semibold">Debug Info</h3>
  <p class="mb-2 text-sm">Room ID: {roomId}</p>
  <pre class="max-h-[60vh] overflow-auto rounded bg-gray-100 p-2 text-xs dark:bg-gray-900">{JSON.stringify(members, null, 2)}</pre>
  <button class="mt-4 rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600" on:click={closeInfo}>
    Close
  </button>
</Modal>

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
