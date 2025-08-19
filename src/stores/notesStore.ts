import { writable } from 'svelte/store';
import * as storage from '../services/storage'; // Adjusted path to be relative
import { v4 as uuidv4 } from 'uuid';

// --- Types ---
export interface Note {
  id: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

// --- Store ---
export const notes = writable<Note[]>([]);

const STORE_NAME = 'notes';

// --- Actions ---

/**
 * Loads all notes from IndexedDB into the store.
 * Should be called when the application initializes.
 */
export async function initNotesStore() {
  if (typeof window === 'undefined') return;
  try {
    const storedNotes = await storage.getAll<Note>(STORE_NAME);
    notes.set(storedNotes.sort((a, b) => b.updatedAt - a.updatedAt));
  } catch (error) {
    console.error("Failed to initialize notes store:", error);
    notes.set([]);
  }
}

/**
 * Creates a new note, saves it to storage, and updates the store.
 * @param {string} content - The content of the new note.
 */
export async function addNote(content: string) {
  const newNote: Note = {
    id: uuidv4(),
    content,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  await storage.set(STORE_NAME, newNote);
  notes.update(allNotes => [newNote, ...allNotes].sort((a, b) => b.updatedAt - a.updatedAt));
}

/**
 * Updates the content of an existing note.
 * @param {string} id - The ID of the note to update.
 * @param {string} content - The new content for the note.
 */
export async function updateNote(id: string, content: string) {
  notes.update(allNotes => {
    const noteIndex = allNotes.findIndex(n => n.id === id);
    if (noteIndex === -1) {
      console.warn(`Note with id ${id} not found for update.`);
      return allNotes;
    }

    const updatedNote: Note = { ...allNotes[noteIndex], content, updatedAt: Date.now() };
    storage.set(STORE_NAME, updatedNote);

    const newNotes = [...allNotes];
    newNotes[noteIndex] = updatedNote;

    // Sort again to bring the most recently updated to the top
    return newNotes.sort((a, b) => b.updatedAt - a.updatedAt);
  });
}

/**
 * Deletes a note from storage and the store.
 * @param {string} id - The ID of the note to delete.
 */
export async function deleteNote(id: string) {
  await storage.del(STORE_NAME, id);
  notes.update(allNotes => allNotes.filter(n => n.id !== id));
}
