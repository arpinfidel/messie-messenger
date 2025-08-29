<script lang="ts">
  import { onMount } from 'svelte'
  import { TodoViewModel } from '../../viewmodels/todo/TodoViewModel'
  import type {
    TodoList,
    TodoItem,
    UpdateTodoItem,
  } from '../../api/generated/models'
  import { createEventDispatcher } from 'svelte'

  export let listId: string

  const dispatch = createEventDispatcher()
  const todoViewModel = new TodoViewModel()

  let todoList: TodoList | undefined
  let todoItems: TodoItem[] = []
  let newTodoItemTitle: string = ''
  let newTodoItemDescription: string = ''
  let newTodoItemDueDate: string = ''

  onMount(async () => {
    await fetchTodoListDetails()
  })

  async function fetchTodoListDetails() {
    try {
      const fetchedList = await todoViewModel.getTodoListById(listId)
      if (fetchedList) {
        todoList = fetchedList
        const fetchedItems = await todoViewModel.getTodoItemsByListId(listId)
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
            position: (item as any).position, // Access position
          }))
          .sort((a, b) => (a.position || '').localeCompare(b.position || '')) // Sort by position, handle undefined
      }
    } catch (error) {
      console.error('Error fetching todo list details:', error)
    }
  }

  async function handleAddTodoItem() {
    if (!newTodoItemTitle.trim() || !todoList?.id) return

    try {
      const dueDate = newTodoItemDueDate
        ? new Date(newTodoItemDueDate)
        : undefined
      const lastItem = todoItems[todoItems.length - 1]
      const prevItemId = lastItem ? lastItem.id : null

      await todoViewModel.createTodoItem(
        todoList.id,
        newTodoItemTitle,
        newTodoItemDescription,
        dueDate
      )
      newTodoItemTitle = ''
      newTodoItemDescription = ''
      newTodoItemDueDate = ''
      await fetchTodoListDetails() // Refresh items
    } catch (error) {
      console.error('Error adding todo item:', error)
    }
  }

  async function handleToggleComplete(item: TodoItem) {
    try {
      const updatedItem: UpdateTodoItem = {
        completed: !item.completed,
      }
      await todoViewModel.updateTodoItem(todoList!.id, item.id!, updatedItem)
      await fetchTodoListDetails() // Refresh items
    } catch (error) {
      console.error('Error toggling todo item completion:', error)
    }
  }

  let editingItemId: string | null = null
  let editedItemTitle: string = ''
  let editedItemDescription: string = ''
  let editedItemDueDate: string = ''

  function startEdit(item: TodoItem) {
    editingItemId = item.id!
    editedItemTitle = item.title!
    editedItemDescription = item.description || ''
    editedItemDueDate = item.dueDate
      ? item.dueDate.toISOString().split('T')[0]
      : ''
  }

  async function saveEdit(item: TodoItem) {
    if (!editedItemTitle.trim()) return

    try {
      const dueDate = editedItemDueDate
        ? new Date(editedItemDueDate)
        : undefined
      const updatedItem: UpdateTodoItem = {
        title: editedItemTitle,
        description: editedItemDescription,
        dueDate: dueDate,
      }
      await todoViewModel.updateTodoItem(todoList!.id, item.id!, updatedItem)
      editingItemId = null
      await fetchTodoListDetails() // Refresh items
    } catch (error) {
      console.error('Error saving todo item edit:', error)
    }
  }

  function cancelEdit() {
    editingItemId = null
  }

  async function handleReorderTodoItem(itemId: string, newIndex: number) {
    const itemToMove = todoItems.find((item) => item.id === itemId)
    if (!itemToMove) return

    const oldIndex = todoItems.indexOf(itemToMove)
    if (oldIndex === newIndex) return

    // Remove item from old position
    todoItems.splice(oldIndex, 1)
    // Insert item at new position
    todoItems.splice(newIndex, 0, itemToMove)

    // Determine prev and next item IDs for fractional indexing
    const prevItem = newIndex > 0 ? todoItems[newIndex - 1] : null
    const nextItem =
      newIndex < todoItems.length - 1 ? todoItems[newIndex + 1] : null

    try {
      await todoViewModel.updateTodoItemPosition(
        itemId,
        todoList!.id,
        prevItem ? prevItem.id : null,
        nextItem ? nextItem.id : null
      )
      await fetchTodoListDetails() // Refresh to get updated positions from backend
    } catch (error) {
      console.error('Error reordering todo item:', error)
      // Revert local changes if backend update fails
      await fetchTodoListDetails()
    }
  }

  function closeDetailPanel() {
    dispatch('close')
  }
</script>

<div class="todo-detail-panel p-4 bg-white shadow-lg rounded-lg">
  <button
    on:click={closeDetailPanel}
    class="float-right text-gray-500 hover:text-gray-700">X</button
  >
  {#if todoList}
    <h2 class="text-2xl font-bold mb-4">{todoList.title}</h2>
    <p class="text-gray-600 mb-4">{todoList.description}</p>

    <h3 class="text-xl font-semibold mb-3">Todo Items</h3>
    <ul class="space-y-2">
      {#each todoItems as item (item.id)}
        <li class="flex items-center justify-between bg-gray-50 p-2 rounded-md">
          <div class="flex items-center">
            <input
              type="checkbox"
              checked={item.completed}
              on:change={() => handleToggleComplete(item)}
              class="mr-2"
            />
            <span class={item.completed ? 'line-through text-gray-500' : ''}>
              {item.title}
              {#if item.dueDate}
                <span class="text-sm text-gray-400 ml-2"
                  >({new Date(item.dueDate).toLocaleDateString()})</span
                >
              {/if}
            </span>
          </div>
          <div class="flex items-center space-x-2">
            {#if editingItemId === item.id}
              <button
                on:click={() => saveEdit(item)}
                class="text-green-500 hover:text-green-700 text-sm">Save</button
              >
              <button
                on:click={cancelEdit}
                class="text-red-500 hover:text-red-700 text-sm">Cancel</button
              >
            {:else}
              <button
                on:click={() => startEdit(item)}
                class="text-blue-500 hover:text-blue-700 text-sm">Edit</button
              >
              <!-- Reorder buttons (simplified for now, could be drag-and-drop) -->
              <button
                on:click={() =>
                  handleReorderTodoItem(item.id, todoItems.indexOf(item) - 1)}
                disabled={todoItems.indexOf(item) === 0}
                class="text-gray-500 hover:text-gray-700 text-sm">▲</button
              >
              <button
                on:click={() =>
                  handleReorderTodoItem(item.id, todoItems.indexOf(item) + 1)}
                disabled={todoItems.indexOf(item) === todoItems.length - 1}
                class="text-gray-500 hover:text-gray-700 text-sm">▼</button
              >
            {/if}
          </div>
        </li>
        {#if editingItemId === item.id}
          <li class="bg-gray-100 p-2 rounded-md mt-1 mb-2">
            <input
              type="text"
              bind:value={editedItemTitle}
              placeholder="Item title"
              class="w-full p-1 border rounded-md mb-1"
            />
            <textarea
              bind:value={editedItemDescription}
              placeholder="Item description (optional)"
              class="w-full p-1 border rounded-md mb-1"
            ></textarea>
            <input
              type="date"
              bind:value={editedItemDueDate}
              class="w-full p-1 border rounded-md mb-1"
            />
          </li>
        {/if}
      {/each}
    </ul>

    <div class="mt-6 p-4 border rounded-md bg-gray-50">
      <h4 class="text-lg font-semibold mb-2">Add New Todo Item</h4>
      <input
        type="text"
        bind:value={newTodoItemTitle}
        placeholder="Item title"
        class="w-full p-2 border rounded-md mb-2"
      />
      <textarea
        bind:value={newTodoItemDescription}
        placeholder="Item description (optional)"
        class="w-full p-2 border rounded-md mb-2"
      ></textarea>
      <input
        type="date"
        bind:value={newTodoItemDueDate}
        class="w-full p-2 border rounded-md mb-2"
      />
      <button
        on:click={handleAddTodoItem}
        class="w-full bg-blue-500 text-white p-2 rounded-md hover:bg-blue-600"
        >Add Item</button
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
