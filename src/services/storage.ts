import { openDB, DBSchema, IDBPDatabase } from 'idb';

const DB_NAME = 'unified-messenger-app';
const DB_VERSION = 4; // Incremented version to trigger upgrade

// Define the database schema.
// We'll add more object stores here as we add features.
interface AppDB extends DBSchema {
  notes: {
    key: string;
    value: any; // Using 'any' here for a generic service, the type will be enforced in the specific store
  };
  todos: {
    key: string;
    value: any;
  };
  calendarEvents: {
    key: string;
    value: any;
  };
  emails: {
    key: string;
    value: any;
  };
}

let dbPromise: Promise<IDBPDatabase<AppDB>> | null = null;

function getDb(): Promise<IDBPDatabase<AppDB>> {
  if (typeof window === 'undefined') {
    // Return a mock DB for SSR or environments without a window object
    return Promise.resolve(null as any);
  }

  if (!dbPromise) {
    dbPromise = openDB<AppDB>(DB_NAME, DB_VERSION, {
      upgrade(db, oldVersion) {
        // Create object stores for each feature if they don't exist
        if (!db.objectStoreNames.contains('notes')) {
          db.createObjectStore('notes', { keyPath: 'id' });
        }
        // Add new stores in upgrade callbacks
        if (oldVersion < 2) {
          if (!db.objectStoreNames.contains('todos')) {
            db.createObjectStore('todos', { keyPath: 'id' });
          }
        }
        if (oldVersion < 3) {
          if (!db.objectStoreNames.contains('calendarEvents')) {
            db.createObjectStore('calendarEvents', { keyPath: 'id' });
          }
        }
        if (oldVersion < 4) {
          if (!db.objectStoreNames.contains('emails')) {
            db.createObjectStore('emails', { keyPath: 'id' });
          }
        }
      },
    });
  }
  return dbPromise;
}

/**
 * Retrieves a value from a specific object store by its key.
 * @param storeName - The name of the object store.
 * @param key - The key of the item to retrieve.
 */
export async function get<T>(storeName: keyof AppDB['objectStoreNames'], key: string): Promise<T | undefined> {
  const db = await getDb();
  if (!db) return undefined;
  return db.get(storeName, key);
}

/**
 * Retrieves all values from a specific object store.
 * @param storeName - The name of the object store.
 */
export async function getAll<T>(storeName: keyof AppDB['objectStoreNames']): Promise<T[]> {
  const db = await getDb();
  if (!db) return [];
  return db.getAll(storeName);
}

/**
 * Adds or updates a value in a specific object store.
 * @param storeName - The name of the object store.
 * @param value - The value to add or update.
 */
export async function set(storeName: keyof AppDB['objectStoreNames'], value: any): Promise<string | undefined> {
  const db = await getDb();
  if (!db) return undefined;
  return db.put(storeName, value);
}

/**
 * Deletes a value from a specific object store by its key.
 * @param storeName - The name of the object store.
 * @param key - The key of the item to delete.
 */
export async function del(storeName: keyof AppDB['objectStoreNames'], key: string): Promise<void> {
  const db = await getDb();
  if (!db) return;
  return db.delete(storeName, key);
}
