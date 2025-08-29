<script lang="ts">
  import { onMount } from 'svelte';
  import { TodoViewModel } from '../../viewmodels/todo/TodoViewModel';
  import type { TodoList, TodoItem, UpdateTodoItem } from '../../api/generated/models';
  import { createEventDispatcher } from 'svelte';

  export let listId: string;

  const dispatch = createEventDispatcher();
  const todoViewModel = new TodoViewModel();

  let todoList: TodoList | undefined;
  let todoItems: TodoItem[] = [];
  let newTodoItemTitle: string = '';
  let newTodoItemDescription: string = '';
  let newTodoItemDueDate: string = '';

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
    if (!newTodoItemTitle.trim() || !todoList?.id) return;

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

  function startEdit(item: TodoItem) {
    editingItemId = item.id!;
    editedItemTitle = item.title!;
    editedItemDescription = item.description || '';
    editedItemDueDate = item.dueDate ? item.dueDate.toISOString().split('T')[0] : '';
  }

  async function saveEdit(item: TodoItem) {
    if (!editedItemTitle.trim()) return;

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
      editingItemId = null;
      await fetchTodoListDetails(); // Refresh items
    } catch (error) {
      console.error('Error saving todo item edit:', error);
    }
  }

  function cancelEdit() {
    editingItemId = null;
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
    <h2 class="mb-4 text-2xl font-bold">{todoList.title}</h2>
    <p class="mb-4 text-gray-600">{todoList.description}</p>

    <h3 class="mb-3 text-xl font-semibold">Todo Items</h3>
    <ul class="space-y-2">
      {#each todoItems as item (item.id)}
        <li class="flex items-center justify-between rounded-md bg-gray-50 p-2">
          <div class="flex items-center">
            <input
              type="checkbox"
              checked={item.completed}
              on:change={() => handleToggleComplete(item)}
              class="mr-2"
            />
            <span class={item.completed ? 'text-gray-500 line-through' : ''}>
              {item.title}
              {#if item.dueDate}
                <span class="ml-2 text-sm text-gray-400"
                  >({new Date(item.dueDate).toLocaleDateString()})</span
                >
              {/if}
            </span>
          </div>
          <div class="flex items-center space-x-2">
            {#if editingItemId === item.id}
              <button
                on:click={() => saveEdit(item)}
                class="text-sm text-green-500 hover:text-green-700">Save</button
              >
              <button on:click={cancelEdit} class="text-sm text-red-500 hover:text-red-700"
                >Cancel</button
              >
            {:else}
              <button
                on:click={() => startEdit(item)}
                class="text-sm text-blue-500 hover:text-blue-700">Edit</button
              >
              <!-- Reorder buttons (simplified for now, could be drag-and-drop) -->
              <button
                on:click={() => handleReorderTodoItem(item.id, todoItems.indexOf(item) - 1)}
                disabled={todoItems.indexOf(item) === 0}
                class="text-sm text-gray-500 hover:text-gray-700">▲</button
              >
              <button
                on:click={() => handleReorderTodoItem(item.id, todoItems.indexOf(item) + 1)}
                disabled={todoItems.indexOf(item) === todoItems.length - 1}
                class="text-sm text-gray-500 hover:text-gray-700">▼</button
              >
            {/if}
          </div>
        </li>
        {#if editingItemId === item.id}
          <li class="mb-2 mt-1 rounded-md bg-gray-100 p-2">
            <input
              type="text"
              bind:value={editedItemTitle}
              placeholder="Item title"
              class="mb-1 w-full rounded-md border p-1"
            />
            <textarea
              bind:value={editedItemDescription}
              placeholder="Item description (optional)"
              class="mb-1 w-full rounded-md border p-1"
            ></textarea>
            <input
              type="date"
              bind:value={editedItemDueDate}
              class="mb-1 w-full rounded-md border p-1"
            />
          </li>
        {/if}
      {/each}
    </ul>

    <div class="mt-6 rounded-md border bg-gray-50 p-4">
      <h4 class="mb-2 text-lg font-semibold">Add New Todo Item</h4>
      <input
        type="text"
        bind:value={newTodoItemTitle}
        placeholder="Item title"
        class="mb-2 w-full rounded-md border p-2"
      />
      <textarea
        bind:value={newTodoItemDescription}
        placeholder="Item description (optional)"
        class="mb-2 w-full rounded-md border p-2"
      ></textarea>
      <input
        type="date"
        bind:value={newTodoItemDueDate}
        class="mb-2 w-full rounded-md border p-2"
      />
      <button
        on:click={handleAddTodoItem}
        class="w-full rounded-md bg-blue-500 p-2 text-white hover:bg-blue-600">Add Item</button
      >
    </div>
  {:else}
    <p>Loading todo list details...</p>
  {/if}
</div>

<style>
  .todo-detail-panel {
    max-width: 600px;
    margin: 0 auto;
  }
</style>
