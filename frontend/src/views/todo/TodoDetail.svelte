<script lang="ts">
  function onNewItemKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') handleAddTodoItem();
  }

  import { TodoViewModel } from '../../viewmodels/todo/TodoViewModel';
  import type { TodoList, TodoItem, UpdateTodoItem, UpdateTodoList } from '../../api/generated/models';
  import { createEventDispatcher, tick } from 'svelte';

  // ============= Utilities =============
  function debounce<T extends (...args: any[]) => void>(fn: T, delay: number) {
    let t: ReturnType<typeof setTimeout> | null = null;
    const d = function (this: ThisParameterType<T>, ...args: Parameters<T>) {
      if (t) clearTimeout(t);
      t = setTimeout(() => fn.apply(this, args), delay);
    } as T & { cancel: () => void; flush: (...args: Parameters<T>) => void };
    d.cancel = () => { if (t) { clearTimeout(t); t = null; } };
    d.flush = function (this: ThisParameterType<T>, ...args: Parameters<T>) {
      if (t) { clearTimeout(t); t = null; }
      fn.apply(this, args);
    };
    return d;
  }
  const perItemDebounce = new Map<string, ReturnType<typeof debounce>>();
  function schedulePerItem(id: string, fn: () => void, ms = 400) {
    let d = perItemDebounce.get(id);
    if (!d) {
      d = debounce(fn, ms);
      perItemDebounce.set(id, d);
    } else {
      d.cancel();
      d = debounce(fn, ms);
      perItemDebounce.set(id, d);
    }
    d();
  }
  function cancelPerItem(id: string) {
    const d = perItemDebounce.get(id);
    if (d) d.cancel();
  }

  // ============= Per-item Save Manager =============
  type PutFn = (itemId: string, payload: UpdateTodoItem, signal?: AbortSignal) => Promise<void>;
  class SaveManager {
    private inFlight = new Map<string, { reqId: number; ctrl: AbortController }>();
    private nextId = new Map<string, number>();
    private queued = new Map<string, UpdateTodoItem>();
    private lastSent = new Map<string, string>(); // JSON string for light dedupe

    constructor(private put: PutFn) {}

    enqueue(itemId: string, payload: UpdateTodoItem) {
      const key = JSON.stringify(payload);
      if (this.lastSent.get(itemId) === key && !this.inFlight.has(itemId) && !this.queued.has(itemId)) {
        return;
      }
      this.queued.set(itemId, payload);
      if (!this.inFlight.has(itemId)) this.runNext(itemId);
    }

    cancel(itemId: string) {
      const cur = this.inFlight.get(itemId);
      if (cur) cur.ctrl.abort();
      this.inFlight.delete(itemId);
      this.queued.delete(itemId);
    }

    private async runNext(itemId: string) {
      const payload = this.queued.get(itemId);
      if (!payload) return;

      const id = (this.nextId.get(itemId) ?? 0) + 1;
      this.nextId.set(itemId, id);
      this.queued.delete(itemId);

      const ctrl = new AbortController();
      this.inFlight.set(itemId, { reqId: id, ctrl });

      try {
        await this.put(itemId, payload, ctrl.signal);
        this.lastSent.set(itemId, JSON.stringify(payload));
      } catch (e: any) {
        if (e?.name !== 'AbortError') {
          console.error('PUT failed for', itemId, e);
        }
      } finally {
        const cur = this.inFlight.get(itemId);
        if (!cur || cur.reqId !== id) return; // stale completion
        this.inFlight.delete(itemId);
        if (this.queued.has(itemId)) this.runNext(itemId);
      }
    }
  }

  // ============= Component State =============
  export let listId: string;

  const dispatch = createEventDispatcher();
  const todoViewModel = TodoViewModel.getInstance();

  let todoList: TodoList | undefined;
  let todoItems: TodoItem[] = [];

  let newTodoItemTitle = '';
  let newTodoItemDescription = '';
  let newTodoItemDueDate = '';

  // lock set for items during reorder to block edits
  const posLock = new Set<string>();

  // SaveManager instance
  const saveManager = new SaveManager(async (itemId, payload) => {
    await todoViewModel.updateTodoItem(todoList!.id, itemId, payload);
  });

  // List title/desc saver
  const debouncedSaveTodoListTitle = debounce(async (list: TodoList) => {
    try {
      const updatedList: UpdateTodoList = { title: list.title, description: list.description };
      await todoViewModel.updateTodoList(list.id, updatedList);
    } catch (error) {
      console.error('Error saving todo list title:', error);
    }
  }, 500);

  // helper so TS narrows in event handlers
  function saveListOnBlur() {
    if (!todoList) return;
    debouncedSaveTodoListTitle(todoList);
  }

  $: if (listId) fetchTodoListDetails();

  async function fetchTodoListDetails() {
    try {
      const fetchedList = await todoViewModel.getTodoListById(listId);
      if (!fetchedList) return;
      todoList = fetchedList;
      const fetchedItems = await todoViewModel.getTodoItemsByListId(listId);
      todoItems = fetchedItems
        .map((item: TodoItem) => ({
          id: item.id!,
          listId: item.listId!,
          title: item.title || '',
          description: item.description || '',
          completed: !!item.completed,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
          dueDate: item.dueDate,
          position: item.position,
        }))
        .sort((a, b) => (a.position || '').localeCompare(b.position || ''));
    } catch (error) {
      console.error('Error fetching todo list details:', error);
    }
  }

  // ============= PUT payload builder (full resource) =============
  function buildPutPayload(
    itemId: string,
    patch: Partial<Pick<UpdateTodoItem, 'title' | 'description' | 'dueDate' | 'completed'>>
  ): UpdateTodoItem | null {
    const cur = todoItems.find((i) => i.id === itemId);
    if (!cur) return null;

    const title = (patch.title ?? cur.title ?? '').trim();
    if (!title) return null; // never send empty title

    return {
      title,
      description: patch.description ?? cur.description ?? '',
      dueDate: patch.dueDate ?? cur.dueDate,
      completed: patch.completed ?? !!cur.completed,
      position: cur.position, // preserve position for PUT
    };
  }

  function scheduleEditSave(item: TodoItem, patch: Partial<UpdateTodoItem>) {
    const id = item.id!;
    if (posLock.has(id)) return; // don't write during reorder
    const payload = buildPutPayload(id, patch);
    if (!payload) return;
    schedulePerItem(id, () => saveManager.enqueue(id, payload), 400);
  }

  // ============= Handlers =============
  async function handleAddTodoItem() {
    const title = newTodoItemTitle.trim();
    if (!title || !todoList?.id) return;
    try {
      const dueDate = newTodoItemDueDate ? new Date(newTodoItemDueDate) : undefined;
      await todoViewModel.createTodoItem(todoList.id, title, newTodoItemDescription, dueDate);
      newTodoItemTitle = '';
      newTodoItemDescription = '';
      newTodoItemDueDate = '';
      await fetchTodoListDetails();
    } catch (error) {
      console.error('Error adding todo item:', error);
    }
  }

  function handleToggleComplete(item: TodoItem) {
    const idx = todoItems.findIndex((i) => i.id === item.id);
    if (idx !== -1) {
      const next = [...todoItems];
      next[idx] = { ...next[idx], completed: !next[idx].completed };
      todoItems = next;
    }
    scheduleEditSave(item, { completed: !item.completed });
  }

  function onTitleInput(e: Event, item: TodoItem) {
    const el = e.currentTarget as HTMLInputElement;
    const v = el.value ?? '';
    const idx = todoItems.findIndex((i) => i.id === item.id);
    if (idx !== -1) {
      const next = [...todoItems];
      next[idx] = { ...next[idx], title: v };
      todoItems = next;
    }
    if (v.trim().length === 0) return;
    scheduleEditSave(item, { title: v });
  }

  function onTitleBlur(e: Event, item: TodoItem) {
    const el = e.currentTarget as HTMLInputElement;
    const v = (el.value ?? '').trim();
    if (v.length === 0) {
      const cur = todoItems.find((i) => i.id === item.id);
      el.value = (cur?.title || '').trim();
      return;
    }
    cancelPerItem(item.id!);
    const payload = buildPutPayload(item.id!, {
      title: v,
      description: item.description || '',
      dueDate: item.dueDate,
      completed: item.completed
    });
    if (payload) saveManager.enqueue(item.id!, payload);
  }

  function onTitleKeydown(e: KeyboardEvent & { currentTarget: HTMLInputElement }) {
    if (e.key === 'Enter') e.currentTarget.blur();
  }

  function onDescInput(e: Event, item: TodoItem) {
    const el = e.currentTarget as HTMLTextAreaElement;
    const v = el.value ?? '';
    const idx = todoItems.findIndex((i) => i.id === item.id);
    if (idx !== -1) {
      const next = [...todoItems];
      next[idx] = { ...next[idx], description: v };
      todoItems = next;
    }
    scheduleEditSave(item, { description: v });
  }

  function onDueInput(e: Event, item: TodoItem) {
    const el = e.currentTarget as HTMLInputElement;
    const v = el.value;
    const date = v ? new Date(v) : undefined;
    const idx = todoItems.findIndex((i) => i.id === item.id);
    if (idx !== -1) {
      const next = [...todoItems];
      next[idx] = { ...next[idx], dueDate: date };
      todoItems = next;
    }
    scheduleEditSave(item, { dueDate: date });
  }

  async function handleReorderTodoItem(itemId: string, newIndex: number) {
    const oldIndex = todoItems.findIndex((i) => i.id === itemId);
    if (oldIndex === -1) return;
    if (newIndex < 0 || newIndex >= todoItems.length || newIndex === oldIndex) return;

    cancelPerItem(itemId);
    saveManager.cancel(itemId);
    posLock.add(itemId);

    const before = [...todoItems];
    const moving = todoItems[oldIndex];
    const next = [...todoItems];
    next.splice(oldIndex, 1);
    next.splice(newIndex, 0, moving);
    todoItems = next;

    const prevItem = newIndex > 0 ? todoItems[newIndex - 1] : null;
    const nextItem = newIndex < todoItems.length - 1 ? todoItems[newIndex + 1] : null;

    try {
      await todoViewModel.updateTodoItemPosition(
        itemId,
        todoList!.id,
        prevItem ? prevItem.id : null,
        nextItem ? nextItem.id : null
      );
    } catch (error) {
      console.error('Error reordering todo item:', error);
      todoItems = before; // rollback on failure
    } finally {
      posLock.delete(itemId);
    }
  }

  let editingItemId: string | null = null;
  let editedItemTitle = '';
  let editedItemDescription = '';
  let editedItemDueDate = '';
  async function startEdit(item: TodoItem) {
    editingItemId = item.id!;
    editedItemTitle = item.title || '';
    editedItemDescription = item.description || '';
    editedItemDueDate = item.dueDate ? item.dueDate.toISOString().split('T')[0] : '';
    await tick();
    const inputElement = document.querySelector<HTMLInputElement>(`#item-title-${item.id}`);
    if (inputElement) inputElement.focus();
  }
  function cancelEdit() {
    editingItemId = null;
    fetchTodoListDetails();
  }

  function closeDetailPanel() {
    dispatch('close');
  }

  // flush debounces on tab hide
  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') {
        perItemDebounce.forEach((d) => d.flush());
      }
    });
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
        bind:value={todoList.title}
        on:blur={saveListOnBlur}
        placeholder="List title"
        class="w-full bg-transparent text-xl font-semibold text-white outline-none placeholder:text-gray-500"
      />

      <!-- List description -->
      <textarea
        bind:value={todoList.description}
        on:blur={saveListOnBlur}
        placeholder="List description..."
        class="w-full resize-none rounded-xl border border-[#444] bg-[#2a2a2a] p-3 text-gray-200 outline-none transition-[box-shadow,border-color] focus:border-blue-500 focus:shadow-[0_0_0_2px_rgba(59,130,246,0.2)]"
      ></textarea>

      <!-- Items -->
      <ul class="flex flex-col gap-2">
        {#each todoItems as item, i (item.id)}
          <li class="group relative flex items-center justify-between rounded-xl bg-[#2a2a2a] p-2 transition-colors hover:bg-[#333]">
            <div class="flex w-full items-center">
              <!-- Checkbox -->
              <div
                class="flex h-5 w-5 items-center justify-center rounded border-2 transition-colors
                       {item.completed ? 'border-blue-500 bg-blue-500' : 'border-gray-500'}"
                on:click={() => handleToggleComplete(item)}
              >
                {#if item.completed}
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-white" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                  </svg>
                {/if}
              </div>

              <!-- Title -->
              <input
                type="text"
                id={"item-title-" + item.id}
                bind:value={item.title}
                minlength="1"
                on:keydown={onTitleKeydown}
                on:input={(e) => onTitleInput(e, item)}
                on:blur={(e) => onTitleBlur(e, item)}
                class="ml-2 w-full bg-transparent text-gray-200 outline-none placeholder:text-gray-500 {item.completed ? 'text-gray-400 line-through' : ''}"
                placeholder="Untitled item"
              />
            </div>

            <!-- Reorder controls -->
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
                  <path fill-rule="evenodd" d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z" clip-rule="evenodd"/>
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
                  <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd"/>
                </svg>
              </button>
            </div>
          </li>

          <!-- Expanded editor -->
          {#if editingItemId === item.id}
            <li class="rounded-xl bg-[#2a2a2a] p-3">
              <textarea
                bind:value={item.description}
                on:input={(e) => onDescInput(e, item)}
                on:blur={() => {
                  const payload = buildPutPayload(item.id, {
                    title: item.title,
                    description: item.description || '',
                    dueDate: item.dueDate,
                    completed: item.completed
                  });
                  if (payload) saveManager.enqueue(item.id, payload);
                }}
                placeholder="Item description (optional)"
                class="mb-2 w-full resize-none rounded-lg border border-[#444] bg-[#1f2937] p-2 text-gray-200 outline-none transition-[box-shadow,border-color] focus:border-blue-500 focus:shadow-[0_0_0_2px_rgba(59,130,246,0.2)]"
              ></textarea>

              <input
                type="date"
                value={item.dueDate ? item.dueDate.toISOString().split('T')[0] : ''}
                on:input={(e) => onDueInput(e, item)}
                on:blur={() => {
                  const payload = buildPutPayload(item.id, {
                    title: item.title,
                    description: item.description || '',
                    dueDate: item.dueDate,
                    completed: item.completed
                  });
                  if (payload) saveManager.enqueue(item.id, payload);
                }}
                class="w-full rounded-lg border border-[#444] bg-[#1f2937] p-2 text-gray-200 outline-none transition-[box-shadow,border-color] focus:border-blue-500 focus:shadow-[0_0_0_2px_rgba(59,130,246,0.2)]"
              />
            </li>
          {/if}
        {/each}

        <!-- New Todo Item Input (moved inside ul, no mt-[-1]) -->
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
