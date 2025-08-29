import { writable, type Readable } from 'svelte/store';
import type { TimelineItem } from '../../models/shared/TimelineItem';
import type { IModuleViewModel } from '../shared/IModuleViewModel';
import { DefaultApi, Configuration } from '../../api/generated';
import type {
  NewTodoItem,
  UpdateTodoItem,
  TodoList,
  TodoItem,
  User,
} from '../../api/generated/models';
import { generatePosition, getInitialPosition } from '../../utils/fractionalIndexing';
import { CloudAuthViewModel } from '@/viewmodels/cloud-auth/CloudAuthViewModel';

const cloudAuthViewModel = CloudAuthViewModel.getInstance();

export class TodoViewModel implements IModuleViewModel {
  private todoApi: DefaultApi;
  private _timelineItems = writable<TimelineItem[]>([]);

  constructor() {
    // TODO: Get base path from a configuration service
    const config = new Configuration({
      basePath: 'http://localhost:8080/api/v1',
      accessToken: () => cloudAuthViewModel.jwtToken || '',
    });
    this.todoApi = new DefaultApi(config);
  }

  async initialize(): Promise<void> {
    console.log('TodoViewModel initialized');
    await this.fetchAndTransformTodos();
  }

  getTimelineItems(): Readable<TimelineItem[]> {
    return this._timelineItems;
  }

  getSettingsComponent(): any {
    // TODO: Implement a settings component for Todo module
    return null;
  }

  getModuleName(): string {
    return 'Todo';
  }

  public async fetchAndTransformTodos(): Promise<void> {
    try {
      const todoLists: TodoList[] = await this.todoApi.getTodoListsByUserId({
        userId: cloudAuthViewModel.userID || '',
      });
      let allTimelineItems: TimelineItem[] = [];

      for (const list of todoLists) {
        // Add the todo list itself as a timeline item
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

        const todoItems: TodoItem[] = await this.todoApi.getTodoItemsByListId({ listId: list.id });

        const transformedItems: TimelineItem[] = todoItems.map((item) => ({
          id: item.id,
          type: 'todo',
          title: item.title,
          description: item.description,
          timestamp: item.updatedAt
            ? item.updatedAt.getTime()
            : item.createdAt
              ? item.createdAt.getTime()
              : 0,
          completed: item.completed,
          dueDate: item.dueDate ? item.dueDate.getTime() : undefined,
          listId: item.listId,
          position: (item as any).position, // Cast to any to access position
        }));
        allTimelineItems = allTimelineItems.concat(transformedItems);
      }

      // Sort all timeline items by timestamp (last opened/updated)
      allTimelineItems.sort((a, b) => b.timestamp - a.timestamp);

      this._timelineItems.set(allTimelineItems);
    } catch (error) {
      console.error('Error fetching and transforming todo items:', error);
      this._timelineItems.set([]); // Clear items on error
    }
  }

  async getTodoListById(listId: string): Promise<TodoList | undefined> {
    try {
      const todoList = await this.todoApi.getTodoListById({ listId });
      return todoList;
    } catch (error) {
      console.error(`Error fetching todo list with ID ${listId}:`, error);
      return undefined;
    }
  }

  async updateTodoItem(
    listId: string,
    itemId: string,
    updateTodoItem: UpdateTodoItem
  ): Promise<void> {
    try {
      await this.todoApi.updateTodoItem({ listId, itemId, updateTodoItem });
      await this.fetchAndTransformTodos(); // Refresh the list
    } catch (error) {
      console.error(`Error updating todo item ${itemId}:`, error);
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
      const todoItems = await this.todoApi.getTodoItemsByListId({ listId });
      let prevPosition: string | null = null;
      let nextPosition: string | null = null;

      if (prevPosition) {
        prevPosition =
          (todoItems.find((item) => item.id === prevPosition) as any)?.position || null;
      }
      if (nextPosition) {
        nextPosition =
          (todoItems.find((item) => item.id === nextPosition) as any)?.position || null;
      }

      const position = generatePosition(prevPosition, nextPosition);

      const newTodoItem: NewTodoItem = {
        listId,
        title,
        description,
        position,
        dueDate: dueDate, // dueDate is already a Date object
      };

      await this.todoApi.createTodoItem({ listId, newTodoItem });
      await this.fetchAndTransformTodos(); // Refresh the list
    } catch (error) {
      console.error('Error creating todo item:', error);
      throw error;
    }
  }

  async getTodoItemsByListId(listId: string): Promise<TodoItem[]> {
    try {
      const todoItems = await this.todoApi.getTodoItemsByListId({ listId });
      return todoItems;
    } catch (error) {
      console.error(`Error fetching todo items for list ${listId}:`, error);
      return [];
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
        prevPosition = (todoItems.find((item) => item.id === prevItemId) as any)?.position || null;
      }
      if (nextItemId) {
        nextPosition = (todoItems.find((item) => item.id === nextItemId) as any)?.position || null;
      }

      const position = generatePosition(prevPosition, nextPosition);

      const updateTodoItem: UpdateTodoItem = {
        position: position,
      } as UpdateTodoItem; // Cast to UpdateTodoItem to allow position, prevItemId, nextItemId

      await this.todoApi.updateTodoItem({ listId, itemId, updateTodoItem });
      await this.fetchAndTransformTodos(); // Refresh the list
    } catch (error) {
      console.error('Error updating todo item position:', error);
      throw error;
    }
  }
}
