<script lang="ts">
  import { createEventDispatcher, onDestroy, tick } from 'svelte';
  import { TodoViewModel, type TodoDetailItem } from '../../viewmodels/todo/TodoViewModel';
  import type { TodoList } from '../../api/generated/models';

  export let listId: string;

  const dispatch = createEventDispatcher();
  const todoViewModel = TodoViewModel.getInstance();

  let todoList: TodoList | null = null;
  let todoItems: TodoDetailItem[] = [];

  const unsubscribers: Array<() => void> = [];
  unsubscribers.push(
    todoViewModel.getSelectedList().subscribe((value) => {
      todoList = value;
    })
  );
  unsubscribers.push(
    todoViewModel.getSelectedItems().subscribe((value) => {
      todoItems = value;
    })
  );

  let visibilityHandler: (() => void) | null = null;
  if (typeof document !== 'undefined') {
    visibilityHandler = () => {
      if (document.visibilityState === 'hidden') {
        todoViewModel.flushPendingItemUpdates();
      }
    };
    document.addEventListener('visibilitychange', visibilityHandler);
  }

  onDestroy(() => {
    unsubscribers.forEach((unsubscribe) => unsubscribe());
    if (visibilityHandler && typeof document !== 'undefined') {
      document.removeEventListener('visibilitychange', visibilityHandler);
    }
  });

  let currentListId: string | null = null;
  $: if (listId && listId !== currentListId) {
    currentListId = listId;
    void todoViewModel.selectTodoList(listId);
  }

  let newTodoItemTitle = '';
  let newTodoItemDescription = '';
  let newTodoItemDueDate = '';

  function onNewItemKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') handleAddTodoItem();
  }

  async function handleAddTodoItem() {
    if (!todoList?.id) return;
    const title = newTodoItemTitle.trim();
    if (!title) return;
    const dueDate = newTodoItemDueDate ? new Date(newTodoItemDueDate) : undefined;

    try {
      await todoViewModel.createTodoItem(todoList.id, title, newTodoItemDescription, dueDate);
      newTodoItemTitle = '';
      newTodoItemDescription = '';
      newTodoItemDueDate = '';
    } catch (error) {
      console.error('Error adding todo item:', error);
    }
  }

  function handleToggleComplete(item: TodoDetailItem) {
    todoViewModel.toggleItemCompletion(item.id);
  }

  function onTitleInput(event: Event, item: TodoDetailItem) {
    const value = (event.currentTarget as HTMLInputElement).value ?? '';
    todoViewModel.updateItemDraft(item.id, { title: value });
  }

  async function onTitleBlur(event: Event, item: TodoDetailItem) {
    const value = ((event.currentTarget as HTMLInputElement).value ?? '').trim();
    if (!value) {
      await todoViewModel.reloadSelectedListDetail();
      return;
    }
    try {
      await todoViewModel.commitItemNow(item.id);
    } catch (error) {
      console.error('Error saving todo item title:', error);
    }
  }

  function onTitleKeydown(e: KeyboardEvent & { currentTarget: HTMLInputElement }) {
    if (e.key === 'Enter') e.currentTarget.blur();
  }

  function onDescInput(event: Event, item: TodoDetailItem) {
    const value = (event.currentTarget as HTMLTextAreaElement).value ?? '';
    todoViewModel.updateItemDraft(item.id, { description: value });
  }

  async function onDescBlur(item: TodoDetailItem) {
    try {
      await todoViewModel.commitItemNow(item.id);
    } catch (error) {
      console.error('Error saving todo item description:', error);
    }
  }

  function onDueInput(event: Event, item: TodoDetailItem) {
    const value = (event.currentTarget as HTMLInputElement).value ?? '';
    const date = value ? new Date(value) : undefined;
    todoViewModel.updateItemDraft(item.id, { dueDate: date });
  }

  async function onDueBlur(item: TodoDetailItem) {
    try {
      await todoViewModel.commitItemNow(item.id);
    } catch (error) {
      console.error('Error saving todo item due date:', error);
    }
  }

  async function handleReorderTodoItem(itemId: string, newIndex: number) {
    try {
      await todoViewModel.reorderSelectedItem(itemId, newIndex);
    } catch (error) {
      console.error('Error reordering todo item:', error);
    }
  }

  let editingItemId: string | null = null;

  async function startEdit(item: TodoDetailItem) {
    editingItemId = item.id;
    await tick();
    const inputElement = document.querySelector<HTMLInputElement>(`#item-title-${item.id}`);
    if (inputElement) inputElement.focus();
  }

  async function cancelEdit() {
    editingItemId = null;
    await todoViewModel.reloadSelectedListDetail();
  }

  function closeDetailPanel() {
    dispatch('close');
  }

  function onListTitleInput(event: Event) {
    const value = (event.currentTarget as HTMLInputElement).value ?? '';
    todoViewModel.updateSelectedListDraft({ title: value });
  }

  async function onListTitleBlur(event: Event) {
    const value = ((event.currentTarget as HTMLInputElement).value ?? '').trim();
    if (!value) {
      await todoViewModel.reloadSelectedListDetail();
      return;
    }
    try {
      await todoViewModel.persistSelectedListDraft();
    } catch (error) {
      console.error('Error saving list title:', error);
    }
  }

  function onListDescriptionInput(event: Event) {
    const value = (event.currentTarget as HTMLTextAreaElement).value ?? '';
    todoViewModel.updateSelectedListDraft({ description: value });
  }

  async function onListDescriptionBlur() {
    try {
      await todoViewModel.persistSelectedListDraft();
    } catch (error) {
      console.error('Error saving list description:', error);
    }
  }
</script>

<!-- Panel -->
<div class="flex h-full flex-col bg-[#1e1e1e] text-gray-200">
  <!-- Header -->
  <div class="flex items-center justify-between border-b border-[#333] px-6 py-4">
    <div class="flex items-center space-x-3">
      <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-blue-500 to-indigo-600 shadow-lg">
        <svg class="h-5 w-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
        </svg>
      </div>
      <div>
        <h2 class="text-lg font-semibold text-gray-100">{todoList?.title || 'Todo List'}</h2>
        <p class="text-sm text-gray-400">{todoItems.length} items</p>
      </div>
    </div>

    <div class="flex items-center space-x-2">
      <button
        on:click={closeDetailPanel}
        class="rounded-lg p-2 text-gray-400 transition-colors hover:bg-gray-700 hover:text-gray-200"
        title="Close panel"
      >
        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  </div>

  <!-- Body -->
  <div class="flex flex-1 flex-col gap-4 overflow-y-auto px-6 py-4">
    {#if todoList}
      <!-- List title -->
      <input
        type="text"
        value={todoList?.title ?? ''}
        on:input={onListTitleInput}
        on:blur={onListTitleBlur}
        placeholder="List title"
        class="w-full bg-transparent text-xl font-semibold text-white outline-none placeholder:text-gray-500"
      />

      <!-- List description -->
      <textarea
        value={todoList?.description ?? ''}
        on:input={onListDescriptionInput}
        on:blur={onListDescriptionBlur}
        placeholder="List description..."
        class="w-full resize-none rounded-xl border border-[#444] bg-[#2a2a2a] p-3 text-gray-200 outline-none transition-[box-shadow,border-color] focus:border-blue-500 focus:shadow-[0_0_0_2px_rgba(59,130,246,0.2)]"
      ></textarea>

      <!-- Items -->
      <ul class="flex flex-col gap-2">
        {#each todoItems as item, i (item.id)}
          <li class="group relative flex items-center justify-between rounded-xl bg-[#2a2a2a] p-2 transition-colors hover:bg-[#333]">
            <div class="flex w-full items-center" on:dblclick={() => startEdit(item)}>
              <div
                class="flex h-5 w-5 items-center justify-center rounded border-2 transition-colors {item.completed ? 'border-blue-500 bg-blue-500' : 'border-gray-500'}"
                on:click={() => handleToggleComplete(item)}
              >
                {#if item.completed}
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-white" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                  </svg>
                {/if}
              </div>

              <input
                id={"item-title-" + item.id}
                type="text"
                value={item.title}
                minlength="1"
                on:keydown={onTitleKeydown}
                on:input={(event) => onTitleInput(event, item)}
                on:blur={(event) => onTitleBlur(event, item)}
                class="ml-2 w-full bg-transparent text-gray-200 outline-none placeholder:text-gray-500 {item.completed ? 'text-gray-400 line-through' : ''}"
                placeholder="Untitled item"
              />
            </div>

            <div class="absolute right-2 top-1/2 flex -translate-y-1/2 transform flex-col opacity-0 transition-opacity group-hover:opacity-100">
              <button
                on:mousedown|preventDefault
                on:click|stopPropagation={() => handleReorderTodoItem(item.id, i - 1)}
                disabled={i === 0}
                class="rounded p-1 text-gray-400 transition-colors hover:bg-gray-700 hover:text-gray-200 disabled:opacity-40"
                aria-label="Move up"
                title="Move up"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z" clip-rule="evenodd" />
                </svg>
              </button>
              <button
                on:mousedown|preventDefault
                on:click|stopPropagation={() => handleReorderTodoItem(item.id, i + 1)}
                disabled={i === todoItems.length - 1}
                class="rounded p-1 text-gray-400 transition-colors hover:bg-gray-700 hover:text-gray-200 disabled:opacity-40"
                aria-label="Move down"
                title="Move down"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
                </svg>
              </button>
            </div>
          </li>

          {#if editingItemId === item.id}
            <li class="rounded-xl bg-[#2a2a2a] p-3">
              <textarea
                value={item.description ?? ''}
                on:input={(event) => onDescInput(event, item)}
                on:blur={() => onDescBlur(item)}
                placeholder="Item description (optional)"
                class="mb-2 w-full resize-none rounded-lg border border-[#444] bg-[#1f2937] p-2 text-gray-200 outline-none transition-[box-shadow,border-color] focus:border-blue-500 focus:shadow-[0_0_0_2px_rgba(59,130,246,0.2)]"
              ></textarea>

              <input
                type="date"
                value={item.dueDate ? item.dueDate.toISOString().split('T')[0] : ''}
                on:input={(event) => onDueInput(event, item)}
                on:blur={() => onDueBlur(item)}
                class="w-full rounded-lg border border-[#444] bg-[#1f2937] p-2 text-gray-200 outline-none transition-[box-shadow,border-color] focus:border-blue-500 focus:shadow-[0_0_0_2px_rgba(59,130,246,0.2)]"
              />

              <div class="mt-3 flex justify-end space-x-2">
                <button
                  class="rounded-lg px-3 py-1 text-sm text-gray-400 transition-colors hover:bg-gray-700 hover:text-gray-200"
                  on:click={cancelEdit}
                >
                  Cancel
                </button>
              </div>
            </li>
          {/if}
        {/each}

        <li class="group relative flex items-center justify-between rounded-xl bg-[#2a2a2a] p-2 transition-colors hover:bg-[#333]">
          <div class="flex w-full items-center">
            <div class="flex h-5 w-5 items-center justify-center rounded {newTodoItemTitle.trim() !== '' ? 'border-2 border-gray-500' : ''}"></div>
            <input
              type="text"
              bind:value={newTodoItemTitle}
              on:keydown={onNewItemKeydown}
              on:blur={handleAddTodoItem}
              placeholder="Add a new todo item... (Enter to add)"
              class="ml-2 w-full bg-transparent text-gray-200 outline-none placeholder:text-gray-500"
            />
          </div>
        </li>
      </ul>
    {:else}
      <p class="text-gray-400">Loading todo list details...</p>
    {/if}
  </div>
</div>

<style>
  /* No custom selectors needed; Tailwind-only to avoid css-unused-selector warnings. */
</style>
