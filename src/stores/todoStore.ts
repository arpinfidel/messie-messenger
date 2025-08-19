import { writable } from 'svelte/store';
import * as storage from '../services/storage';
import { v4 as uuidv4 } from 'uuid';

// --- Types ---
export interface Todo {
  id: string;
  text: string;
  completed: boolean;
  createdAt: number;
  updatedAt: number;
}

// --- Store ---
export const todos = writable<Todo[]>([]);
const STORE_NAME = 'todos';

// --- Actions ---

/**
 * Loads all todos from IndexedDB into the store.
 */
export async function initTodoStore() {
  if (typeof window === 'undefined') return;
  try {
    const storedTodos = await storage.getAll<Todo>(STORE_NAME);
    // Sort by creation time, incomplete tasks first
    todos.set(storedTodos.sort((a, b) => {
      if (a.completed === b.completed) {
        return a.createdAt - b.createdAt;
      }
      return a.completed ? 1 : -1;
    }));
  } catch (error) {
    console.error("Failed to initialize todo store:", error);
    todos.set([]);
  }
}

/**
 * Creates a new todo, saves it, and adds it to the store.
 * @param {string} text - The content of the todo.
 */
export async function addTodo(text: string) {
  const newTodo: Todo = {
    id: uuidv4(),
    text,
    completed: false,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  await storage.set(STORE_NAME, newTodo);
  todos.update(allTodos => [...allTodos, newTodo]);
}

/**
 * Toggles the completion status of a todo.
 * @param {string} id - The ID of the todo to toggle.
 */
export async function toggleTodo(id: string) {
  todos.update(allTodos => {
    const todoIndex = allTodos.findIndex(t => t.id === id);
    if (todoIndex === -1) return allTodos;

    const updatedTodo = { ...allTodos[todoIndex], completed: !allTodos[todoIndex].completed, updatedAt: Date.now() };
    storage.set(STORE_NAME, updatedTodo);

    const newTodos = [...allTodos];
    newTodos[todoIndex] = updatedTodo;
    return newTodos;
  });
}

/**
 * Deletes a todo from storage and the store.
 * @param {string} id - The ID of the todo to delete.
 */
export async function deleteTodo(id: string) {
  await storage.del(STORE_NAME, id);
  todos.update(allTodos => allTodos.filter(t => t.id !== id));
}

/**
 * Updates the text of a todo.
 * @param {string} id - The ID of the todo to update.
 * @param {string} text - The new text for the todo.
 */
export async function updateTodoText(id: string, text: string) {
    todos.update(allTodos => {
        const todoIndex = allTodos.findIndex(t => t.id === id);
        if (todoIndex === -1) return allTodos;

        const updatedTodo = { ...allTodos[todoIndex], text, updatedAt: Date.now() };
        storage.set(STORE_NAME, updatedTodo);

        const newTodos = [...allTodos];
        newTodos[todoIndex] = updatedTodo;
        return newTodos;
    });
}
