<!-- UnifiedTimeline.svelte -->
<script lang="ts">
  import { onMount, createEventDispatcher, onDestroy } from 'svelte';
  import { UnifiedTimelineViewModel } from '@/viewmodels/shared/UnifiedTimelineViewModel';
  import { MatrixViewModel } from '@/viewmodels/matrix/MatrixViewModel';
  import { EmailViewModel } from '@/viewmodels/email/EmailViewModel';
  import type { TimelineItem } from '@/models/shared/TimelineItem';
  import { DefaultApi } from '@/api/generated/apis/DefaultApi';
  import type { NewTodoList } from '@/api/generated/models/NewTodoList';
  import LoadingIndicator from './LoadingIndicator.svelte';
  import { CloudAuthViewModel } from '@/viewmodels/cloud-auth/CloudAuthViewModel';
  import { Configuration, DefaultConfig } from '@/api/generated';
  import { TodoViewModel } from '@/viewmodels/todo/TodoViewModel';
  import GenericTimelineItem from './timeline/GenericTimelineItem.svelte';

  const dispatch = createEventDispatcher();

  export let timelineWidth: number;
  export let timelineLeft: number;

  let items: TimelineItem[] = [];
  let isLoading = true;
  let error: string | null = null;
  let loadingModuleNames: string[] = [];
  let loadingText = 'Loading timeline items...';
  let showCreateDropdown = false;

  const unifiedTimelineViewModel = new UnifiedTimelineViewModel();
  const cloudAuthViewModel = CloudAuthViewModel.getInstance();
  const todoViewModel = TodoViewModel.getInstance();

  let createButton: HTMLButtonElement;
  let createDropdown: HTMLDivElement;

  function handleClickOutside(event: MouseEvent) {
    if (
      showCreateDropdown &&
      createDropdown &&
      !createDropdown.contains(event.target as Node) &&
      !createButton.contains(event.target as Node)
    ) {
      showCreateDropdown = false;
    }
  }

  onMount(async () => {
    unifiedTimelineViewModel.isLoading.subscribe((value) => {
      isLoading = value;
    });

    document.addEventListener('click', handleClickOutside, true);

    unifiedTimelineViewModel.loadingModuleNames.subscribe((value) => {
      loadingModuleNames = value;
    });

    try {
      unifiedTimelineViewModel.getSortedTimelineStore().subscribe((value: TimelineItem[]) => {
        items = value;
      });
    } catch (e: any) {
      error = e.message;
    }
  });

  onDestroy(() => {
    document.removeEventListener('click', handleClickOutside, true);
  });

  $: loadingText = loadingModuleNames.length > 0 ? `Loading: ${loadingModuleNames.join(', ')}` : '';

  function selectItem(event: CustomEvent<TimelineItem>) {
    dispatch('itemSelected', event.detail);
  }

  async function createTodoList() {
    showCreateDropdown = false;
    if (!cloudAuthViewModel.jwtToken) {
      console.error('User not authenticated. Cannot create todo list.');
      return;
    }

    const config = new Configuration({
      accessToken: () => cloudAuthViewModel.jwtToken || '',
    });
    const api = new DefaultApi(config);
    const newTodoList: NewTodoList = { title: 'New Todo List', description: '' };

    try {
      const response = await api.createTodoList({ newTodoList });
      console.log('Todo list created successfully:', response);
      await todoViewModel.fetchAndTransformTodos();
      alert('Todo list created successfully!');
    } catch (error: any) {
      console.error('Failed to create todo list:', error);
      alert(`Failed to create todo list: ${error.message || 'Unknown error'}`);
    }
  }
</script>

<div class="timeline-container flex-1 overflow-y-auto bg-white dark:bg-gray-900">
  <!-- Enhanced Header -->
  <div class="sticky top-0 z-20 border-b border-gray-200/80 dark:border-gray-700/80">
    <div class="px-6 py-4">
      <div class="flex items-center justify-between">
        <!-- App Title -->
        <div class="flex items-center space-x-3">
          <div class="flex h-12 w-12 items-center justify-center rounded-xl bg-gray-100 dark:bg-gray-800 shadow-lg">
            <img src="/messie-logo.svg" alt="Messie Logo" class="h-12 w-12 text-gray-600 dark:text-gray-300" />
          </div>
          <h1 class="text-3xl font-bold text-gray-600 dark:text-gray-300">
            Messie
          </h1>
        </div>

        <!-- Action Buttons -->
        <div class="flex items-center space-x-3">
          <!-- Create Button with Dropdown -->
          <div class="relative">
            <button
              bind:this={createButton}
              class="group flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-r from-emerald-500 to-green-600 text-white shadow-lg transition-all duration-300 hover:scale-105 hover:shadow-xl hover:from-emerald-400 hover:to-green-500 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
              on:click={() => (showCreateDropdown = !showCreateDropdown)}
              aria-haspopup="true"
              aria-expanded={showCreateDropdown}
              title="Create new item"
            >
              <svg 
                class="h-5 w-5 transition-transform duration-300 {showCreateDropdown ? 'rotate-45' : ''}" 
                fill="none" 
                stroke="currentColor" 
                viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
              </svg>
            </button>

            {#if showCreateDropdown}
              <div
                bind:this={createDropdown}
                class="absolute right-0 top-full z-30 mt-2 w-56 origin-top-right animate-in fade-in slide-in-from-top-2 rounded-xl border border-gray-200 bg-white/95 py-2 shadow-xl backdrop-blur-md dark:border-gray-700 dark:bg-gray-800/95"
              >
                <button
                  class="flex w-full items-center px-4 py-3 text-left text-gray-700 transition-colors hover:bg-gray-100/80 dark:text-gray-300 dark:hover:bg-gray-700/80"
                  on:click={createTodoList}
                >
                  <div class="mr-3 flex h-8 w-8 items-center justify-center rounded-lg bg-purple-100 dark:bg-purple-900/50">
                    <span class="text-sm">✅</span>
                  </div>
                  <div>
                    <div class="font-medium">Create todo list</div>
                    <div class="text-xs text-gray-500 dark:text-gray-400">Add a new task list</div>
                  </div>
                </button>
              </div>
            {/if}
          </div>

          <!-- Settings Button -->
          <button
            class="flex h-11 items-center space-x-2 rounded-xl bg-white px-4 py-2 font-medium text-gray-700 shadow-md ring-1 ring-gray-200 transition-all duration-300 hover:bg-gray-50 hover:shadow-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-gray-300 dark:ring-gray-700 dark:hover:bg-gray-700 dark:focus:ring-offset-gray-900"
            on:click={() => dispatch('openSettings')}
          >
            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Content Area -->
  <div class="px-6 py-6">
    {#if error}
      <!-- Enhanced Error State -->
      <div class="rounded-xl border border-red-200 bg-red-50 p-6 dark:border-red-800 dark:bg-red-900/20">
        <div class="flex items-center">
          <div class="flex h-10 w-10 items-center justify-center rounded-full bg-red-100 dark:bg-red-900/50">
            <svg class="h-5 w-5 text-red-600 dark:text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
            </svg>
          </div>
          <div class="ml-4">
            <h3 class="font-medium text-red-800 dark:text-red-200">Error Loading Timeline</h3>
            <p class="mt-1 text-sm text-red-700 dark:text-red-300">{error}</p>
          </div>
        </div>
      </div>
    {:else if items.length === 0 && !isLoading}
      <!-- Enhanced Empty State -->
      <div class="flex flex-col items-center justify-center py-16 text-center">
        <div class="mb-6 flex h-24 w-24 items-center justify-center rounded-full bg-gradient-to-br from-gray-100 to-gray-200 dark:from-gray-800 dark:to-gray-700">
          <svg class="h-12 w-12 text-gray-400 dark:text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
          </svg>
        </div>
        <h3 class="mb-2 text-xl font-semibold text-gray-900 dark:text-gray-100">No timeline items yet</h3>
        <p class="mb-6 max-w-md text-gray-600 dark:text-gray-400">
          Get started by connecting your accounts or creating your first todo list. Your messages, emails, and tasks will appear here.
        </p>
        <button
          class="flex items-center space-x-2 rounded-xl bg-gradient-to-r from-blue-500 to-purple-600 px-6 py-3 font-medium text-white shadow-lg transition-all duration-300 hover:scale-105 hover:shadow-xl"
          on:click={() => (showCreateDropdown = !showCreateDropdown)}
        >
          <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
          </svg>
          <span>Create your first item</span>
        </button>
      </div>
    {:else}
      <!-- Timeline Items -->
      <div class="space-y-4">
        {#each items as item (item.id)}
          <GenericTimelineItem {item} on:itemSelected={selectItem} />
        {/each}
      </div>
    {/if}
  </div>
</div>

<!-- Sidebar-scoped loading bar at the bottom -->
<div class="px-0">
  <LoadingIndicator
    show={isLoading}
    text={loadingText}
    mode="inline"
  />
</div>

<style>
  .timeline-container {
    min-height: 100vh;
  }
  
  /* Smooth animations */
  @keyframes animate-in {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }
  
  .animate-in {
    animation: animate-in 0.2s ease-out;
  }
  
  /* Fade in animation */
  @keyframes fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }
  
  .fade-in {
    animation: fade-in 0.15s ease-out;
  }
  
  /* Slide in from top */
  @keyframes slide-in-from-top-2 {
    from { transform: translateY(-8px); }
    to { transform: translateY(0); }
  }
  
  .slide-in-from-top-2 {
    animation: slide-in-from-top-2 0.15s ease-out;
  }
</style>
