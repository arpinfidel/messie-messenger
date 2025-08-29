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

  const dispatch = createEventDispatcher();

  export let timelineWidth: number;
  export let timelineLeft: number;

  let items: TimelineItem[] = [];
  let isLoading = true; // Renamed from 'loading' for consistency
  let error: string | null = null;
  let loadingModuleNames: string[] = []; // Declare at top level
  let loadingText = 'Loading timeline items...'; // New variable for loading text
  let showCreateDropdown = false; // Declare new variable for dropdown visibility

  const unifiedTimelineViewModel = new UnifiedTimelineViewModel();
  const cloudAuthViewModel = CloudAuthViewModel.getInstance();
  const todoViewModel = new TodoViewModel();

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
        // console.log(`[UnifiedTimeline] Sorted timeline items updated. Count: ${items.length}`);
      });
    } catch (e: any) {
      error = e.message;
    }
  });

  onDestroy(() => {
    document.removeEventListener('click', handleClickOutside, true);
  });

  $: loadingText = loadingModuleNames.length > 0 ? `Loading: ${loadingModuleNames.join(', ')}` : '';

  // Add a reactive statement to log items when they change
  $: {
    // console.log(`[UnifiedTimeline] Current items array length: ${items.length}`);
  }

  function selectItem(item: TimelineItem) {
    dispatch('itemSelected', item);
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
    const newTodoList: NewTodoList = { title: 'New Todo List' };

    try {
      const response = await api.createTodoList({ newTodoList });
      console.log('Todo list created successfully:', response);
      await todoViewModel.fetchAndTransformTodos(); // Refresh the timeline
      alert('Todo list created successfully!');
    } catch (error: any) {
      console.error('Failed to create todo list:', error);
      alert(`Failed to create todo list: ${error.message || 'Unknown error'}`);
    }
  }
</script>

<div class="flex-1 overflow-y-auto p-4">
  <div class="mb-6 flex items-center justify-between">
    <h1 class="text-3xl font-bold">Mess</h1>
    <div class="relative">
      <button
        bind:this={createButton}
        class="mr-2 rounded bg-green-500 px-4 py-2 font-bold text-white hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-opacity-50"
        on:click={() => (showCreateDropdown = !showCreateDropdown)}
        aria-haspopup="true"
        aria-expanded={showCreateDropdown}
      >
        +
      </button>
      {#if showCreateDropdown}
        <div
          bind:this={createDropdown}
          class="absolute right-0 top-full z-10 mt-2 w-48 rounded-md bg-white py-1 shadow-lg"
        >
          <button
            class="block w-full px-4 py-2 text-left text-gray-800 hover:bg-gray-100"
            on:click={() => {
              createTodoList();
            }}
          >
            Create todo list
          </button>
        </div>
      {/if}
      <button
        class="rounded bg-blue-500 px-4 py-2 font-bold text-white hover:bg-blue-700"
        on:click={() => dispatch('openSettings')}
      >
        Settings
      </button>
    </div>
  </div>

  {#if error}
    <p class="text-red-500">Error: {error}</p>
  {:else if items.length === 0 && !isLoading}
    <!-- Only show "No items" if no items AND nothing is loading -->
    <p>No timeline items to display.</p>
  {:else}
    <div class="space-y-4">
      {#each items as item (item.id)}
        {#if item.type === 'todo'}
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
        {:else}
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
        {/if}
      {/each}
    </div>
  {/if}
</div>

<LoadingIndicator
  show={isLoading}
  width={`${timelineWidth + 1}px`}
  left={`${timelineLeft}px`}
  text={loadingText}
/>
