<script lang="ts">
  import { onMount } from 'svelte';
  import { TodoViewModel } from '../../viewmodels/todo/TodoViewModel';
  import type { TodoList, TodoItem, UpdateTodoItem, UpdateTodoList } from '../../api/generated/models';
  import { createEventDispatcher, tick } from 'svelte';

  // Temporarily moved debounce function here to resolve import issues
  function debounce<T extends (...args: any[]) => void>(func: T, delay: number): (...args: Parameters<T>) => void {
    let timeout: ReturnType<typeof setTimeout> | null = null;

    return function(this: ThisParameterType<T>, ...args: Parameters<T>): void {
      const context = this;
      if (timeout) {
        clearTimeout(timeout);
      }
      timeout = setTimeout(() => func.apply(context, args), delay);
    };
  }

  export let listId: string;

  const dispatch = createEventDispatcher();
  const todoViewModel = new TodoViewModel();

  let todoList: TodoList | undefined;
  let todoItems: TodoItem[] = [];
  let newTodoItemTitle: string = '';
  let newTodoItemDescription: string = '';
  let newTodoItemDueDate: string = '';

  const debouncedSaveTodoListTitle = debounce(async (list: TodoList) => {
    try {
      const updatedList: UpdateTodoList = {
        title: list.title,
        description: list.description,
      };
      await todoViewModel.updateTodoList(list.id, updatedList);
    } catch (error) {
      console.error('Error saving todo list title:', error);
    }
  }, 500);

  onMount(async () => {
    await fetchTodoListDetails();
  });

  async function fetchTodoListDetails() {
    try {
      const fetchedList = await todoViewModel.getTodoListById(listId);
      if (fetchedList) {
        todoList = fetchedList;
        const fetchedItems = await todoViewModel.getTodoItemsByListId(listId);
        todoItems = fetchedItems
          .map((item) => ({
            id: item.id!,
            listId: item.listId!,
            title: item.title!,
            description: item.description!,
            completed: item.completed || false,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            dueDate: item.dueDate,
            position: item.position, // Access position
          }))
          .sort((a, b) => (a.position || '').localeCompare(b.position || '')); // Sort by position, handle undefined
      }
    } catch (error) {
      console.error('Error fetching todo list details:', error);
    }
  }

  async function handleAddTodoItem() {
    console.log('handleAddTodoItem called. newTodoItemTitle:', newTodoItemTitle);
    if (!newTodoItemTitle.trim() || !todoList?.id) {
      console.log('Attempted to add empty todo item or no list ID.');
      return;
    }
    console.log('Adding todo item with title:', newTodoItemTitle);

    try {
      const dueDate = newTodoItemDueDate ? new Date(newTodoItemDueDate) : undefined;
      const lastItem = todoItems[todoItems.length - 1];
      const prevItemId = lastItem ? lastItem.id : null;

      await todoViewModel.createTodoItem(
        todoList.id,
        newTodoItemTitle,
        newTodoItemDescription,
        dueDate
      );
      newTodoItemTitle = '';
      newTodoItemDescription = '';
      newTodoItemDueDate = '';
      await fetchTodoListDetails(); // Refresh items
    } catch (error) {
      console.error('Error adding todo item:', error);
    }
  }

  async function handleToggleComplete(item: TodoItem) {
    try {
      const updatedItem: UpdateTodoItem = {
        description: item.description,
        position: (item as any).position,
        title: item.title!,
        completed: !item.completed,
      };
      await todoViewModel.updateTodoItem(todoList!.id, item.id!, updatedItem);
      await fetchTodoListDetails(); // Refresh items
    } catch (error) {
      console.error('Error toggling todo item completion:', error);
    }
  }

  let editingItemId: string | null = null;
  let editedItemTitle: string = '';
  let editedItemDescription: string = '';
  let editedItemDueDate: string = '';

  const debouncedSaveEdit = debounce(async (item: TodoItem) => {
    if (!editedItemTitle.trim()) {
      console.log('Attempted to save empty todo item title. Reverting to original.');
      const originalItem = todoItems.find(i => i.id === item.id);
      if (originalItem) {
        editedItemTitle = originalItem.title!;
      }
      return;
    }
    console.log('Saving todo item with title:', editedItemTitle);

    try {
      const dueDate = editedItemDueDate ? new Date(editedItemDueDate) : undefined;
      const updatedItem: UpdateTodoItem = {
        title: editedItemTitle,
        description: editedItemDescription,
        dueDate: dueDate,
        completed: item.completed,
        position: item.position
      };
      await todoViewModel.updateTodoItem(todoList!.id, item.id!, updatedItem);
      // No need to set editingItemId to null or fetchTodoListDetails immediately
      // The UI will reflect the change via reactivity, and a full refresh might disrupt user input
    } catch (error) {
      console.error('Error saving todo item edit:', error);
    }
  }, 500); // Debounce for 500ms

  async function handleItemFieldChange(item: TodoItem, field: 'title' | 'description' | 'dueDate', value: string | Date | undefined) {
    console.log(`Item ${item.id} field ${field} changed to:`, value);
    // Update the local state immediately for a responsive UI
    const index = todoItems.findIndex(i => i.id === item.id);
    if (index !== -1) {
      if (field === 'title') todoItems[index].title = value as string;
      if (field === 'description') todoItems[index].description = value as string;
      if (field === 'dueDate') todoItems[index].dueDate = value as Date | undefined;
      todoItems = [...todoItems]; // Trigger reactivity
    }

    // Update the editedItem state for the debounced save
    if (field === 'title') editedItemTitle = value as string;
    if (field === 'description') editedItemDescription = value as string;
    if (field === 'dueDate') editedItemDueDate = value ? (value as Date).toISOString().split('T')[0] : '';

    // Trigger the debounced save
    debouncedSaveEdit(item);
  }


  async function startEdit(item: TodoItem) {
    editingItemId = item.id!;
    editedItemTitle = item.title!;
    editedItemDescription = item.description || '';
    editedItemDueDate = item.dueDate ? item.dueDate.toISOString().split('T')[0] : '';
    await tick(); // Wait for DOM update
    const inputElement = document.querySelector(`#item-title-${item.id}`);
    if (inputElement) {
      (inputElement as HTMLInputElement).focus();
    }
  }

  function cancelEdit() {
    editingItemId = null;
    // Revert editedItemTitle, etc. if needed, by refetching or storing original values
    fetchTodoListDetails(); // Revert by refetching
  }

  async function handleReorderTodoItem(itemId: string, newIndex: number) {
    const itemToMove = todoItems.find((item) => item.id === itemId);
    if (!itemToMove) return;

    const oldIndex = todoItems.indexOf(itemToMove);
    if (oldIndex === newIndex) return;

    // Remove item from old position
    todoItems.splice(oldIndex, 1);
    // Insert item at new position
    todoItems.splice(newIndex, 0, itemToMove);

    // Determine prev and next item IDs for fractional indexing
    const prevItem = newIndex > 0 ? todoItems[newIndex - 1] : null;
    const nextItem = newIndex < todoItems.length - 1 ? todoItems[newIndex + 1] : null;

    try {
      await todoViewModel.updateTodoItemPosition(
        itemId,
        todoList!.id,
        prevItem ? prevItem.id : null,
        nextItem ? nextItem.id : null
      );
      await fetchTodoListDetails(); // Refresh to get updated positions from backend
    } catch (error) {
      console.error('Error reordering todo item:', error);
      // Revert local changes if backend update fails
      await fetchTodoListDetails();
    }
  }

  function closeDetailPanel() {
    dispatch('close');
  }
</script>

<div class="todo-detail-panel rounded-lg bg-white p-4 shadow-lg">
  <button on:click={closeDetailPanel} class="float-right text-gray-500 hover:text-gray-700"
    >X</button
  >
  {#if todoList}
    <input
      type="text"
      class="mb-4 w-full text-2xl font-bold text-gray-800 focus:outline-none"
      bind:value={todoList.title}
      on:blur={() => todoList && debouncedSaveTodoListTitle(todoList)}
    />
    <textarea
      class="mb-4 w-full resize-none text-gray-800 focus:outline-none"
      bind:value={todoList.description}
      on:blur={() => todoList && debouncedSaveTodoListTitle(todoList)}
    ></textarea>

    <ul class="space-y-2 pt-4">
      {#each todoItems as item (item.id)}
        <li
          class="group flex items-center justify-between rounded-md bg-gray-50 p-2 hover:bg-gray-100"
        >
          <div class="flex items-center">
            <!-- Custom Checkbox -->
            <div
              class="flex h-5 w-5 items-center justify-center rounded border-2 {item.completed ? 'border-blue-500 bg-blue-500' : 'border-gray-300'}"
              on:click={() => handleToggleComplete(item)}
            >
              {#if item.completed}
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-4 w-4 text-white"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                >
                  <path
                    fill-rule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              {/if}
            </div>

            <!-- Integrated Input Field -->
            <input
              type="text"
              id="item-title-{item.id}"
              value={item.title}
              on:input={(e) => handleItemFieldChange(item, 'title', e.currentTarget.value)}
              on:blur={() => debouncedSaveEdit(item)}
              class="ml-2 w-full bg-transparent text-gray-800 focus:outline-none {item.completed ? 'text-gray-500 line-through' : ''}"
            />
          </div>
          <div class="flex items-center space-x-2 opacity-0 group-hover:opacity-100">
            <button
              on:click={() => handleReorderTodoItem(item.id, todoItems.indexOf(item) - 1)}
              disabled={todoItems.indexOf(item) === 0}
              class="text-sm text-gray-500 hover:text-gray-700 disabled:opacity-50"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
            <button
              on:click={() => handleReorderTodoItem(item.id, todoItems.indexOf(item) + 1)}
              disabled={todoItems.indexOf(item) === todoItems.length - 1}
              class="text-sm text-gray-500 hover:text-gray-700 disabled:opacity-50"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>
          </div>
        </li>
        <!-- Description and Due Date (only visible when editing) -->
        {#if editingItemId === item.id}
          <li class="mb-2 mt-1 rounded-md bg-gray-100 p-2">
            <textarea
              value={item.description}
              on:input={(e) => handleItemFieldChange(item, 'description', e.currentTarget.value)}
              on:blur={() => debouncedSaveEdit(item)}
              placeholder="Item description (optional)"
              class="mb-1 w-full resize-none rounded-md border p-1 text-gray-800"
            ></textarea>
            <input
              type="date"
              value={editedItemDueDate}
              on:input={(e) => handleItemFieldChange(item, 'dueDate', new Date(e.currentTarget.value))}
              on:blur={() => debouncedSaveEdit(item)}
              class="mb-1 w-full rounded-md border p-1 text-gray-800"
            />
          </li>
        {/if}
      {/each}
    </ul>

    <div class="mt-6">
      <input
        type="text"
        bind:value={newTodoItemTitle}
        on:keydown={(e) => {
          if (e.key === 'Enter') {
            handleAddTodoItem();
          }
        }}
        on:blur={handleAddTodoItem}
        placeholder="Add a new todo item..."
        class="w-full rounded-md border p-2 text-gray-800 focus:outline-none focus:ring-2 focus:ring-blue-500"
      />
    </div>
  {:else}
    <p>Loading todo list details...</p>
  {/if}
</div>

<style>
  /* No specific styles needed here, Tailwind handles most of it */
</style>
