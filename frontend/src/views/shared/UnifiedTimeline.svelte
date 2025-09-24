<!-- UnifiedTimeline.svelte -->
<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte';
  import { UnifiedTimelineViewModel } from '@/viewmodels/shared/UnifiedTimelineViewModel';
  import type { TimelineItem } from '@/models/shared/TimelineItem';
  import LoadingIndicator from './LoadingIndicator.svelte';
  import GenericTimelineItem from './timeline/GenericTimelineItem.svelte';
  import PopupMenu from '@/views/shared/PopupMenu.svelte';
  import type { CreateTodoListState } from '@/viewmodels/todo/TodoViewModel';
  import { MatrixViewModel } from '@/viewmodels/matrix/MatrixViewModel';
  import {
    TIMELINE_SOURCE_FILTERS,
    DEFAULT_TIMELINE_SOURCE_FILTER,
  } from '@/config/timelineSources';
  import {
    AlertCircle,
    BellOff,
    CheckCircle2,
    CheckSquare,
    ListChecks,
    Loader2,
    MessageSquare,
    XCircle,
  } from 'lucide-svelte';

  const dispatch = createEventDispatcher();

  type ItemInteractionDetail = {
    item: TimelineItem;
    originalEvent: MouseEvent | KeyboardEvent | PointerEvent;
    interactionType?: 'click' | 'keyboard' | 'long-press';
  };

  let items: TimelineItem[] = [];
  let isLoading = true;
  let error: string | null = null;
  let loadingModuleNames: string[] = [];
  let loadingText = 'Loading timeline items...';
  let showCreateMenu = false;
  let todoCreationState: CreateTodoListState = { status: 'idle' };
  let creationToast: { type: 'success' | 'error'; message: string } | null = null;
  let creationToastTimer: ReturnType<typeof setTimeout> | null = null;
  let searchTerm = '';
  let selectedSourceFilter = DEFAULT_TIMELINE_SOURCE_FILTER;

  const unifiedTimelineViewModel = new UnifiedTimelineViewModel();
  const sourceOptions = TIMELINE_SOURCE_FILTERS;
  const matrixViewModel = MatrixViewModel.getInstance();

  let createButton: HTMLButtonElement;

  let selectedIds = new Set<string>();
  let selectionAnchorIndex: number | null = null;
  let isMutingSelection = false;
  let selectionFeedback: { type: 'success' | 'error'; message: string } | null = null;
  let selectionFeedbackTimer: ReturnType<typeof setTimeout> | null = null;

  onMount(() => {
    const unsubscribers: Array<() => void> = [];

    unsubscribers.push(
      unifiedTimelineViewModel.isLoading.subscribe((value) => {
        isLoading = value;
      })
    );

    unsubscribers.push(
      unifiedTimelineViewModel.loadingModuleNames.subscribe((value) => {
        loadingModuleNames = value;
      })
    );

    unsubscribers.push(
      unifiedTimelineViewModel.getSearchTermStore().subscribe((value) => {
        searchTerm = value;
      })
    );

    unsubscribers.push(
      unifiedTimelineViewModel.getSourceFilterStore().subscribe((value) => {
        selectedSourceFilter = value;
      })
    );

    unsubscribers.push(
      unifiedTimelineViewModel.getSortedTimelineStore().subscribe((value: TimelineItem[]) => {
        items = value;
      })
    );

    unsubscribers.push(
      unifiedTimelineViewModel.getTodoCreationState().subscribe((state) => {
        todoCreationState = state;
        if (creationToastTimer) {
          clearTimeout(creationToastTimer);
          creationToastTimer = null;
        }

        if (state.status === 'success') {
          creationToast = {
            type: 'success',
            message: 'Todo list created successfully.',
          };
          creationToastTimer = setTimeout(() => {
            creationToast = null;
            unifiedTimelineViewModel.resetTodoCreationState();
          }, 2500);
        } else if (state.status === 'error') {
          creationToast = {
            type: 'error',
            message: state.error ?? 'Failed to create todo list.',
          };
        } else {
          creationToast = null;
        }
      })
    );

    return () => {
      unsubscribers.forEach((unsubscribe) => unsubscribe());
      if (creationToastTimer) {
        clearTimeout(creationToastTimer);
        creationToastTimer = null;
      }
      if (selectionFeedbackTimer) {
        clearTimeout(selectionFeedbackTimer);
        selectionFeedbackTimer = null;
      }
    };
  });

  $: visibleIdSet = new Set(items.map((item) => item.id));
  $: {
    const filteredSelection = new Set(Array.from(selectedIds).filter((id) => visibleIdSet.has(id)));
    if (filteredSelection.size !== selectedIds.size) {
      selectedIds = filteredSelection;
      if (selectionAnchorIndex !== null) {
        const anchorItem = items[selectionAnchorIndex];
        if (!anchorItem || !filteredSelection.has(anchorItem.id)) {
          const fallbackIndex = items.findIndex((it) => filteredSelection.has(it.id));
          selectionAnchorIndex = fallbackIndex >= 0 ? fallbackIndex : null;
        }
      }
    }
  }
  $: selectedItems = items.filter((item) => selectedIds.has(item.id));
  $: selectedMatrixItems = selectedItems.filter((item) => item.type === 'matrix');
  $: selectionCount = selectedItems.length;
  $: matrixSelectionCount = selectedMatrixItems.length;
  $: if (selectionCount > 0) {
    showCreateMenu = false;
  }

  $: loadingText = loadingModuleNames.length > 0 ? `Loading: ${loadingModuleNames.join(', ')}` : '';

  function handleItemInteraction(event: CustomEvent<ItemInteractionDetail>) {
    const { item, originalEvent, interactionType = 'click' } = event.detail;

    if (!item) {
      return;
    }

    if (interactionType === 'keyboard') {
      dispatch('itemSelected', item);
      return;
    }

    const index = items.findIndex((it) => it.id === item.id);
    const pointerEvent = originalEvent as MouseEvent;
    const isShiftSelection = Boolean(pointerEvent?.shiftKey);
    const isModifierSelection = Boolean(pointerEvent?.metaKey || pointerEvent?.ctrlKey);
    const isLongPress = interactionType === 'long-press';
    const selectionModeActive = selectedIds.size > 0;
    const shouldToggleSelection =
      isLongPress || isModifierSelection || (selectionModeActive && !isShiftSelection);

    if (!isShiftSelection && !shouldToggleSelection) {
      dispatch('itemSelected', item);
      if (selectedIds.size === 0) {
        selectionAnchorIndex = null;
      }
      return;
    }

    if (index === -1) {
      dispatch('itemSelected', item);
      return;
    }

    if (isShiftSelection) {
      const anchor = selectionAnchorIndex ?? index;
      const start = Math.min(anchor, index);
      const end = Math.max(anchor, index);
      const rangeIds = items.slice(start, end + 1).map((it) => it.id);
      selectedIds = new Set(rangeIds);
      selectionAnchorIndex = anchor;
      return;
    }

    const next = new Set(selectedIds);
    if (next.has(item.id)) {
      next.delete(item.id);
      if (next.size === 0) {
        selectionAnchorIndex = null;
      } else if (selectionAnchorIndex === index) {
        const fallbackIndex = items.findIndex((it) => next.has(it.id));
        selectionAnchorIndex = fallbackIndex >= 0 ? fallbackIndex : null;
      }
    } else {
      next.add(item.id);
      selectionAnchorIndex = index;
    }
    selectedIds = next;
  }

  function selectAllVisible(): void {
    if (items.length === 0) return;
    selectedIds = new Set(items.map((item) => item.id));
    selectionAnchorIndex = items.length > 0 ? 0 : null;
  }

  function clearSelection(): void {
    selectedIds = new Set();
    selectionAnchorIndex = null;
  }

  function clearSelectionFeedbackTimer() {
    if (selectionFeedbackTimer) {
      clearTimeout(selectionFeedbackTimer);
      selectionFeedbackTimer = null;
    }
  }

  async function muteSelectedRooms(): Promise<void> {
    if (isMutingSelection) return;
    const matrixItems = [...selectedMatrixItems];
    if (matrixItems.length === 0) return;

    isMutingSelection = true;
    clearSelectionFeedbackTimer();

    try {
      const results = await Promise.allSettled(
        matrixItems.map((matrixItem) => matrixViewModel.setRoomMuted(matrixItem.id, true))
      );
      const failedCount = results.reduce(
        (count, result) => (result.status === 'rejected' ? count + 1 : count),
        0
      );

      if (failedCount === 0) {
        selectionFeedback = {
          type: 'success',
          message: `Muted ${matrixItems.length} room${matrixItems.length === 1 ? '' : 's'}.`,
        };
      } else {
        if (failedCount === matrixItems.length) {
          selectionFeedback = {
            type: 'error',
            message: 'Failed to mute selected rooms. Please try again.',
          };
        } else {
          const successfulCount = matrixItems.length - failedCount;
          selectionFeedback = {
            type: 'error',
            message: `Muted ${successfulCount} room${successfulCount === 1 ? '' : 's'}, but ${failedCount} failed.`,
          };
        }
        results.forEach((result, idx) => {
          if (result.status === 'rejected') {
            const roomId = matrixItems[idx]?.id;
            console.error('[UnifiedTimeline] Failed to mute room', roomId, result.reason);
          }
        });
      }
    } catch (err) {
      console.error('[UnifiedTimeline] Unexpected error while muting rooms', err);
      selectionFeedback = {
        type: 'error',
        message: 'Failed to mute selected rooms. Please try again.',
      };
    } finally {
      isMutingSelection = false;
      selectionFeedbackTimer = setTimeout(() => {
        selectionFeedback = null;
        selectionFeedbackTimer = null;
      }, 3000);
    }
  }

  async function createTodoList() {
    showCreateMenu = false;
    try {
      await unifiedTimelineViewModel.createTodoList({ title: 'New Todo List', description: '' });
    } catch (error) {
      console.error('Failed to create todo list:', error);
    }
  }

  function dismissCreationToast() {
    creationToast = null;
    unifiedTimelineViewModel.resetTodoCreationState();
  }

  function handleSearchInput(event: Event) {
    const target = event.currentTarget as HTMLInputElement;
    unifiedTimelineViewModel.setSearchTerm(target.value ?? '');
  }

  function handleSourceFilterChange(event: Event) {
    const target = event.currentTarget as HTMLSelectElement;
    unifiedTimelineViewModel.setSourceFilter(target.value ?? DEFAULT_TIMELINE_SOURCE_FILTER);
  }
</script>

<div class="timeline-container flex-1 overflow-y-auto bg-white dark:bg-gray-900">
  <!-- Enhanced Header -->
  <div class="sticky top-0 z-20 border-b border-gray-200/80 dark:border-gray-700/80">
    <div class="px-6 py-4">
      {#if selectionCount > 0}
        <div class="flex min-h-[4rem] items-center justify-between gap-4">
          <div class="flex flex-1 flex-wrap items-center gap-3 text-blue-900 dark:text-blue-100">
            <div
              class="flex items-center gap-2 rounded-lg bg-blue-100/80 px-3 py-1.5 text-sm font-semibold text-blue-700 dark:bg-blue-900/60 dark:text-blue-100"
              aria-label={`${selectionCount} items selected`}
            >
              <CheckSquare class="h-4 w-4" aria-hidden="true" />
              <span>{selectionCount} selected</span>
            </div>
            <div
              class="flex items-center gap-1 rounded-full bg-blue-50/80 px-2.5 py-1 text-xs font-medium text-blue-700 dark:bg-blue-900/40 dark:text-blue-100"
              aria-label={`${matrixSelectionCount} Matrix rooms selected`}
              title={`${matrixSelectionCount} Matrix rooms selected`}
            >
              <MessageSquare class="h-4 w-4" aria-hidden="true" />
              <span>{matrixSelectionCount}</span>
            </div>
            {#if selectionFeedback}
              <div
                class={`flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium ${
                  selectionFeedback.type === 'success'
                    ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-200'
                    : 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-200'
                }`}
                title={selectionFeedback.message}
                aria-live="polite"
              >
                {#if selectionFeedback.type === 'success'}
                  <CheckCircle2 class="h-4 w-4" aria-hidden="true" />
                {:else}
                  <AlertCircle class="h-4 w-4" aria-hidden="true" />
                {/if}
                <span class="max-w-[12rem] truncate">{selectionFeedback.message}</span>
              </div>
            {/if}
          </div>
          <div class="flex items-center gap-2">
            <button
              class="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-100 text-blue-700 transition-colors hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-blue-900/50 dark:text-blue-100 dark:hover:bg-blue-800"
              on:click={selectAllVisible}
              aria-label="Select all visible"
              title="Select all visible"
            >
              <ListChecks class="h-5 w-5" aria-hidden="true" />
            </button>
            <button
              class="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-600 text-white shadow transition-colors hover:bg-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-blue-100 disabled:cursor-not-allowed disabled:opacity-60 dark:bg-blue-500 dark:hover:bg-blue-400 dark:focus:ring-offset-gray-900"
              on:click={muteSelectedRooms}
              aria-label="Mute selected rooms"
              title="Mute selected rooms"
              disabled={matrixSelectionCount === 0 || isMutingSelection}
            >
              {#if isMutingSelection}
                <Loader2 class="h-5 w-5 animate-spin" aria-hidden="true" />
              {:else}
                <BellOff class="h-5 w-5" aria-hidden="true" />
              {/if}
            </button>
            <button
              class="flex h-10 w-10 items-center justify-center rounded-lg bg-gray-100 text-gray-600 transition-colors hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
              on:click={clearSelection}
              aria-label="Clear selection"
              title="Clear selection"
            >
              <XCircle class="h-5 w-5" aria-hidden="true" />
            </button>
          </div>
        </div>
      {:else}
        <div class="flex min-h-[4rem] items-center justify-between">
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
            <div>
              <button
                bind:this={createButton}
                class="group flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-r from-emerald-500 to-green-600 text-white shadow-lg transition-all duration-300 hover:scale-105 hover:shadow-xl hover:from-emerald-400 hover:to-green-500 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
                on:click={() => (showCreateMenu = !showCreateMenu)}
                aria-haspopup="true"
                aria-expanded={showCreateMenu}
                title="Create new item"
              >
                <svg
                  class="h-5 w-5 transition-transform duration-300 {showCreateMenu ? 'rotate-45' : ''}"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
              </button>

              <PopupMenu anchor={createButton} show={showCreateMenu} on:close={() => (showCreateMenu = false)}>
                <button
                  class="flex w-full items-center px-4 py-3 text-left text-gray-700 transition-colors hover:bg-gray-100/80 disabled:cursor-not-allowed disabled:opacity-60 dark:text-gray-300 dark:hover:bg-gray-700/80"
                  on:click={createTodoList}
                  disabled={todoCreationState.status === 'creating'}
                >
                  <div class="mr-3 flex h-8 w-8 items-center justify-center rounded-lg bg-purple-100 dark:bg-purple-900/50">
                    <span class="text-sm">✅</span>
                  </div>
                  <div>
                    <div class="font-medium">
                      {todoCreationState.status === 'creating' ? 'Creating...' : 'Create todo list'}
                    </div>
                    <div class="text-xs text-gray-500 dark:text-gray-400">
                      {todoCreationState.status === 'creating'
                        ? 'Hang tight while we set things up'
                        : 'Add a new task list'}
                    </div>
                  </div>
                </button>
              </PopupMenu>
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
      {/if}
    </div>
  </div>

  <!-- Content Area -->
  <div class="px-6 py-6">
    <div class="mb-6 grid gap-4 md:grid-cols-[minmax(0,1fr)_220px]">
      <div class="relative">
        <label class="sr-only" for="timeline-search">Search timeline</label>
        <input
          id="timeline-search"
          type="search"
          class="w-full rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm text-gray-700 shadow-sm transition-all focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-200 dark:focus:border-blue-400 dark:focus:ring-blue-400"
          placeholder="Search by title..."
          bind:value={searchTerm}
          on:input={handleSearchInput}
        />
        <svg
          class="pointer-events-none absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M21 21l-4.35-4.35m0 0A7.5 7.5 0 1015 15l4.35 4.35z"
          />
        </svg>
      </div>
      <div>
        <label class="sr-only" for="timeline-source-filter">Filter by source</label>
        <div class="relative">
          <select
            id="timeline-source-filter"
            class="w-full appearance-none rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm text-gray-700 shadow-sm transition-all focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-200 dark:focus:border-blue-400 dark:focus:ring-blue-400"
            bind:value={selectedSourceFilter}
            on:change={handleSourceFilterChange}
          >
            {#each sourceOptions as option}
              <option value={option.id}>{option.label}</option>
            {/each}
          </select>
          <svg
            class="pointer-events-none absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </div>
      </div>
    </div>

    {#if creationToast}
      <div
        class={`mb-4 flex items-start justify-between rounded-lg border px-4 py-3 text-sm ${
          creationToast.type === 'success'
            ? 'border-emerald-200 bg-emerald-50 text-emerald-900 dark:border-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-100'
            : 'border-red-200 bg-red-50 text-red-900 dark:border-red-800 dark:bg-red-900/30 dark:text-red-100'
        }`}
      >
        <span>{creationToast.message}</span>
        <button
          class="ml-4 text-xs font-medium underline-offset-2 hover:underline"
          on:click={dismissCreationToast}
        >
          Dismiss
        </button>
      </div>
    {/if}

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
          on:click={() => (showCreateMenu = !showCreateMenu)}
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
          <GenericTimelineItem
            {item}
            selected={selectedIds.has(item.id)}
            on:itemSelected={handleItemInteraction}
          />
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
