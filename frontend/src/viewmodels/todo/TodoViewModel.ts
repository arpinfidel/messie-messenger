import { writable, type Readable } from 'svelte/store';
import type { TimelineItem } from '../../models/shared/TimelineItem';
import type { IModuleViewModel } from '../shared/IModuleViewModel';
import { DefaultApi, Configuration } from '../../api/generated';
import type {
  NewTodoItem,
  UpdateTodoItem,
  TodoList,
  TodoItem,
  UpdateTodoList,
} from '../../api/generated/models';
import { generatePosition } from '../../utils/fractionalIndexing';
import { CloudAuthViewModel } from '@/viewmodels/cloud-auth/CloudAuthViewModel';

const cloudAuthViewModel = CloudAuthViewModel.getInstance();

export class TodoViewModel implements IModuleViewModel {
  private static instance: TodoViewModel;
  private todoApi: DefaultApi;
  private _timelineItems = writable<TimelineItem[]>([]);
  private pollingInterval: ReturnType<typeof setInterval> | undefined;

  private constructor() {
    const config = new Configuration({
      basePath: 'http://localhost:8080/api/v1',
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
      position: (patch as any).position ?? (cur as any).position,
    };

    return payload;
  }
  // ---------------------------------------------------

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
    } catch (error) {
      console.error(`Error updating todo item ${itemId}:`, error);
      throw error;
    }
  }

  async updateTodoList(listId: string, updateTodoList: UpdateTodoList): Promise<void> {
    try {
      await this.todoApi.updateTodoList({ listId, updateTodoList });
      await this.fetchAndTransformTodos();
    } catch (error) {
      console.error(`Error updating todo list ${listId}:`, error);
      throw error;
    }
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
        prevPosition = (todoItems.find((i) => i.id === prevItemId) as any)?.position || null;
      }
      if (nextItemId) {
        nextPosition = (todoItems.find((i) => i.id === nextItemId) as any)?.position || null;
      }

      const position = generatePosition(prevPosition, nextPosition);

      // Merge the new position with the current item snapshot to avoid wiping fields
      const payload = await this.buildPutPayload(listId, itemId, { position } as UpdateTodoItem);

      await this.todoApi.updateTodoItem({ listId, itemId, updateTodoItem: payload });
      await this.fetchAndTransformTodos();
    } catch (error) {
      console.error('Error updating todo item position:', error);
      throw error;
    }
  }
}
