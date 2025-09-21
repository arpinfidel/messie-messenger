import { writable, get, type Readable } from 'svelte/store';
import type { TimelineItem } from '../../models/shared/TimelineItem';
import type { IModuleViewModel } from '../shared/IModuleViewModel';
import { DefaultApi, Configuration } from '../../api/generated';
import type {
  NewTodoItem,
  NewTodoList,
  UpdateTodoItem,
  TodoList,
  TodoItem,
  UpdateTodoList,
} from '../../api/generated/models';
import { generatePosition } from '../../utils/fractionalIndexing';
import { CloudAuthViewModel } from '@/viewmodels/cloud-auth/CloudAuthViewModel';
import { DetailSaveQueue } from './DetailSaveQueue';
import { getApiBaseUrl } from '@/config/api';

const cloudAuthViewModel = CloudAuthViewModel.getInstance();

export type CreateTodoListState = {
  status: 'idle' | 'creating' | 'success' | 'error';
  error?: string;
  listId?: string;
};

export type TodoDetailItem = {
  id: string;
  listId: string;
  title: string;
  description: string;
  completed: boolean;
  dueDate?: Date;
  createdAt?: Date;
  updatedAt?: Date;
  position?: string | null;
};

type TodoItemPatch = Partial<
  Pick<UpdateTodoItem, 'title' | 'description' | 'dueDate' | 'completed'>
>;

export class TodoViewModel implements IModuleViewModel {
  private static instance: TodoViewModel;
  private todoApi: DefaultApi;
  private _timelineItems = writable<TimelineItem[]>([]);
  private pollingInterval: ReturnType<typeof setInterval> | undefined;
  private readonly initialCreateState: CreateTodoListState = { status: 'idle' };
  private _createTodoListState = writable<CreateTodoListState>(this.initialCreateState);
  private selectedListId: string | null = null;
  private _selectedList = writable<TodoList | null>(null);
  private _selectedItems = writable<TodoDetailItem[]>([]);
  private positionLocks = new Set<string>();
  private detailQueue = new DetailSaveQueue((itemId, payload, signal) =>
    this.performTodoItemUpdate(itemId, payload, signal)
  );

  private constructor() {
    const config = new Configuration({
      basePath: getApiBaseUrl(),
      accessToken: () => cloudAuthViewModel.jwtToken || '',
    });
    this.todoApi = new DefaultApi(config);
  }

  public static getInstance(): TodoViewModel {
    if (!TodoViewModel.instance) {
      TodoViewModel.instance = new TodoViewModel();
    }
    return TodoViewModel.instance;
  }

  async initialize(): Promise<void> {
    await this.fetchAndTransformTodos();
    this.startPolling();
  }

  private startPolling(): void {
    if (this.pollingInterval) clearInterval(this.pollingInterval);
    this.pollingInterval = setInterval(async () => {
      await this.fetchAndTransformTodos();
    }, 10000);
  }

  public stopPolling(): void {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
      this.pollingInterval = undefined;
    }
  }

  getTimelineItems(): Readable<TimelineItem[]> {
    return this._timelineItems;
  }

  getSelectedList(): Readable<TodoList | null> {
    return this._selectedList;
  }

  getSelectedItems(): Readable<TodoDetailItem[]> {
    return this._selectedItems;
  }

  getCreateTodoListState(): Readable<CreateTodoListState> {
    return this._createTodoListState;
  }

  async selectTodoList(listId: string): Promise<void> {
    if (!listId) return;
    if (this.selectedListId !== listId) {
      this.selectedListId = listId;
    }
    await this.refreshSelectedList();
  }

  async reloadSelectedListDetail(): Promise<void> {
    await this.refreshSelectedList();
  }

  getSettingsComponent(): any {
    return null;
  }

  getModuleName(): string {
    return 'Todo';
  }

  public async fetchAndTransformTodos(): Promise<void> {
    try {
      if (!cloudAuthViewModel.jwtToken) {
        return;
      }
      const todoLists: TodoList[] = await this.todoApi.getTodoListsByUserId({
        userId: cloudAuthViewModel.userID || '',
      });

      const allTimelineItems: TimelineItem[] = [];
      for (const list of todoLists) {
        allTimelineItems.push({
          id: list.id,
          type: 'todo',
          title: list.title,
          description: list.description,
          timestamp: list.updatedAt
            ? list.updatedAt.getTime()
            : list.createdAt
              ? list.createdAt.getTime()
              : 0,
          listId: list.id,
        });
      }
      allTimelineItems.sort((a, b) => b.timestamp - a.timestamp);
      this._timelineItems.set(allTimelineItems);
    } catch (error) {
      console.error('Error fetching and transforming todo items:', error);
      this._timelineItems.set([]);
    }
  }

  async getTodoListById(listId: string): Promise<TodoList | undefined> {
    try {
      return await this.todoApi.getTodoListById({ listId });
    } catch (error) {
      console.error(`Error fetching todo list with ID ${listId}:`, error);
      return undefined;
    }
  }

  async getTodoItemsByListId(listId: string): Promise<TodoItem[]> {
    try {
      return await this.todoApi.getTodoItemsByListId({ listId });
    } catch (error) {
      console.error(`Error fetching todo items for list ${listId}:`, error);
      return [];
    }
  }

  // ---------- NEW: helpers to make PUT safe ----------
  private async getItemSnapshot(listId: string, itemId: string): Promise<TodoItem | null> {
    const items = await this.todoApi.getTodoItemsByListId({ listId });
    return items.find((i) => i.id === itemId) ?? null;
  }

  private async buildPutPayload(
    listId: string,
    itemId: string,
    patch: Partial<UpdateTodoItem>
  ): Promise<UpdateTodoItem> {
    const localCandidate =
      this.selectedListId === listId
        ? get(this._selectedItems).find((item) => item.id === itemId)
        : null;

    if (localCandidate) {
      const title = (patch.title ?? localCandidate.title ?? '').trim();
      if (!title) throw new Error('Refusing to PUT empty title');
      return {
        title,
        description: patch.description ?? localCandidate.description ?? '',
        dueDate: patch.dueDate ?? localCandidate.dueDate,
        completed: patch.completed ?? localCandidate.completed,
        position: patch.position ?? localCandidate.position ?? '',
      };
    }

    const cur = await this.getItemSnapshot(listId, itemId);
    if (!cur) {
      throw new Error(`Item ${itemId} not found in list ${listId}`);
    }

    // Resolve fields against current snapshot
    const title = (patch.title ?? cur.title ?? '').trim();
    if (!title) {
      // Never allow empty title on PUT; this is what was blanking your item.
      throw new Error('Refusing to PUT empty title');
    }

    // Always include *all* fields the server stores for the item
    const payload: UpdateTodoItem = {
      title,
      description: patch.description ?? cur.description ?? '',
      dueDate: patch.dueDate ?? cur.dueDate,
      completed: patch.completed ?? !!cur.completed,
      // CRITICAL: always include position so PUT doesn't wipe it
      position: patch.position ?? cur.position,
    };

    return payload;
  }
  // ---------------------------------------------------

  private async performTodoItemUpdate(
    itemId: string,
    payload: UpdateTodoItem,
    signal?: AbortSignal
  ): Promise<void> {
    const listId = this.selectedListId;
    if (!listId) return;
    try {
      const initOverrides = signal ? { signal } : undefined;
      await this.todoApi.updateTodoItem(
        { listId, itemId, updateTodoItem: payload },
        initOverrides
      );
      if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
      await this.fetchAndTransformTodos();
      if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
      if (this.selectedListId === listId) {
        await this.refreshSelectedList();
      }
    } catch (error) {
      if ((error as any)?.name === 'AbortError') {
        throw error;
      }
      console.error('Failed to persist todo item update:', error);
      throw error;
    }
  }

  private normalizeTodoItem(item: TodoItem): TodoDetailItem {
    return {
      id: item.id!,
      listId: item.listId!,
      title: item.title ?? '',
      description: item.description ?? '',
      completed: !!item.completed,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      dueDate: item.dueDate,
      position: item.position ?? '',
    };
  }

  private async refreshSelectedList(): Promise<void> {
    if (!this.selectedListId) {
      this._selectedList.set(null);
      this._selectedItems.set([]);
      return;
    }

    const targetListId = this.selectedListId;
    if (!targetListId) return;

    try {
      const [list, items] = await Promise.all([
        this.todoApi.getTodoListById({ listId: targetListId }),
        this.todoApi.getTodoItemsByListId({ listId: targetListId }),
      ]);

      if (!list) {
        this._selectedList.set(null);
        this._selectedItems.set([]);
        return;
      }

      if (targetListId !== this.selectedListId) {
        return;
      }

      this._selectedList.set(list);
      const normalized = items
        .map((item) => this.normalizeTodoItem(item))
        .sort((a, b) => (a.position ?? '').localeCompare(b.position ?? ''));
      this._selectedItems.set(normalized);
    } catch (error) {
      console.error(`Error refreshing todo list ${this.selectedListId}:`, error);
    }
  }

  async updateTodoItem(
    listId: string,
    itemId: string,
    updateTodoItem: UpdateTodoItem
  ): Promise<void> {
    try {
      // Merge patch with current snapshot to form a full, safe PUT body
      const payload = await this.buildPutPayload(listId, itemId, updateTodoItem);
      await this.todoApi.updateTodoItem({ listId, itemId, updateTodoItem: payload });
      await this.fetchAndTransformTodos();
      if (this.selectedListId === listId) {
        await this.refreshSelectedList();
      }
    } catch (error) {
      console.error(`Error updating todo item ${itemId}:`, error);
      throw error;
    }
  }

  async updateTodoList(
    listId: string,
    updateTodoList: UpdateTodoList,
    options?: { signal?: AbortSignal }
  ): Promise<void> {
    try {
      const initOverrides = options?.signal ? { signal: options.signal } : undefined;
      await this.todoApi.updateTodoList({ listId, updateTodoList }, initOverrides);
      await this.fetchAndTransformTodos();
      if (this.selectedListId === listId) {
        await this.refreshSelectedList();
      }
    } catch (error) {
      console.error(`Error updating todo list ${listId}:`, error);
      throw error;
    }
  }

  async createTodoList(payload: { title: string; description?: string }): Promise<TodoList> {
    const title = payload.title?.trim() ?? '';
    if (!title) {
      throw new Error('Todo list name is required');
    }

    if (!cloudAuthViewModel.jwtToken) {
      throw new Error('User not authenticated');
    }

    try {
      this._createTodoListState.set({ status: 'creating' });
      const newTodoList: NewTodoList = {
        title,
        description: payload.description ?? '',
      };
      const created = await this.todoApi.createTodoList({ newTodoList });
      await this.fetchAndTransformTodos();
      this._createTodoListState.set({ status: 'success', listId: created.id });
      return created;
    } catch (error) {
      console.error('Error creating todo list:', error);
      const message = (error as Error)?.message ?? 'Unable to create todo list';
      this._createTodoListState.set({ status: 'error', error: message });
      throw error;
    }
  }

  resetCreateTodoListState(): void {
    this._createTodoListState.set(this.initialCreateState);
  }

  async createTodoItem(
    listId: string,
    title: string,
    description: string,
    dueDate: Date | undefined
  ): Promise<void> {
    try {
      // New item at end; if you want "at top", set nextPosition to first item’s position instead
      const position = generatePosition(null, null);

      const newTodoItem: NewTodoItem = {
        listId,
        title,
        description,
        position,
        completed: false,
        dueDate,
      };

      await this.todoApi.createTodoItem({ listId, newTodoItem });
      await this.fetchAndTransformTodos();
      if (this.selectedListId === listId) {
        await this.refreshSelectedList();
      }
    } catch (error) {
      console.error('Error creating todo item:', error);
      throw error;
    }
  }

  async updateTodoItemPosition(
    itemId: string,
    listId: string,
    prevItemId: string | null,
    nextItemId: string | null
  ): Promise<void> {
    try {
      const todoItems = await this.todoApi.getTodoItemsByListId({ listId });

      let prevPosition: string | null = null;
      let nextPosition: string | null = null;

      if (prevItemId) {
        prevPosition = todoItems.find((i) => i.id === prevItemId)?.position || null;
      }
      if (nextItemId) {
        nextPosition = todoItems.find((i) => i.id === nextItemId)?.position || null;
      }

      const position = generatePosition(prevPosition, nextPosition);

      // Merge the new position with the current item snapshot to avoid wiping fields
      const payload = await this.buildPutPayload(listId, itemId, { position } as UpdateTodoItem);

      await this.todoApi.updateTodoItem({ listId, itemId, updateTodoItem: payload });
      await this.fetchAndTransformTodos();
      if (this.selectedListId === listId) {
        await this.refreshSelectedList();
      }
    } catch (error) {
      console.error('Error updating todo item position:', error);
      throw error;
    }
  }

  updateSelectedListDraft(patch: Partial<Pick<TodoList, 'title' | 'description'>>): void {
    this._selectedList.update((current) => (current ? { ...current, ...patch } : current));
  }

  async persistSelectedListDraft(): Promise<void> {
    const current = get(this._selectedList);
    if (!current?.id) return;
    const title = (current.title ?? '').trim();
    if (!title) return;
    const payload: UpdateTodoList = {
      title,
      description: current.description ?? '',
    };
    await this.updateTodoList(current.id, payload);
  }

  updateItemDraft(itemId: string, patch: TodoItemPatch): void {
    if (!this.selectedListId || this.positionLocks.has(itemId)) return;

    this._selectedItems.update((items) => {
      const idx = items.findIndex((i) => i.id === itemId);
      if (idx === -1) return items;
      const next = [...items];
      next[idx] = { ...next[idx], ...patch };
      return next;
    });

    const payload = this.buildItemPayload(itemId, patch);
    if (!payload) return;
    this.detailQueue.schedule(itemId, payload);
  }

  async commitItemNow(itemId: string): Promise<void> {
    const payload = this.buildItemPayload(itemId, {});
    if (!payload) return;
    this.detailQueue.cancel(itemId);
    await this.performTodoItemUpdate(itemId, payload);
  }

  toggleItemCompletion(itemId: string): void {
    const items = get(this._selectedItems);
    const current = items.find((i) => i.id === itemId);
    if (!current) return;
    this.updateItemDraft(itemId, { completed: !current.completed });
  }

  async reorderSelectedItem(itemId: string, newIndex: number): Promise<void> {
    if (!this.selectedListId) return;
    const items = get(this._selectedItems);
    const oldIndex = items.findIndex((i) => i.id === itemId);
    if (oldIndex === -1 || newIndex < 0 || newIndex >= items.length || newIndex === oldIndex) {
      return;
    }

    this.detailQueue.cancel(itemId);
    this.positionLocks.add(itemId);

    const before = [...items];
    const reordered = [...items];
    const [moving] = reordered.splice(oldIndex, 1);
    reordered.splice(newIndex, 0, moving);
    this._selectedItems.set(reordered);

    const prevItem = reordered[newIndex - 1] ?? null;
    const nextItem = reordered[newIndex + 1] ?? null;

    try {
      await this.updateTodoItemPosition(
        itemId,
        this.selectedListId,
        prevItem ? prevItem.id : null,
        nextItem ? nextItem.id : null
      );
    } catch (error) {
      this._selectedItems.set(before);
      throw error;
    } finally {
      this.positionLocks.delete(itemId);
    }
  }

  flushPendingItemUpdates(): void {
    this.detailQueue.flushAll((itemId, error) => {
      console.error(`Failed to flush pending update for item ${itemId}:`, error);
    });
  }

  private buildItemPayload(itemId: string, patch: TodoItemPatch): UpdateTodoItem | null {
    const items = get(this._selectedItems);
    const current = items.find((i) => i.id === itemId);
    if (!current) return null;

    const title = (patch.title ?? current.title ?? '').trim();
    if (!title) return null;

    return {
      title,
      description: patch.description ?? current.description ?? '',
      completed: patch.completed ?? current.completed,
      dueDate: patch.dueDate ?? current.dueDate,
      position: current.position ?? '',
    };
  }

}
