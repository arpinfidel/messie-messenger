import { writable } from 'svelte/store';
import * as storage from '../services/storage';
import { v4 as uuidv4 } from 'uuid';

// --- Types ---
export interface CalendarEvent {
  id: string;
  title: string;
  start: number; // Unix timestamp for start time
  end: number;   // Unix timestamp for end time
  createdAt: number;
  updatedAt: number;
}

// --- Store ---
export const calendarEvents = writable<CalendarEvent[]>([]);
const STORE_NAME = 'calendarEvents';

// --- Actions ---

/**
 * Loads all calendar events from IndexedDB into the store.
 */
export async function initCalendarStore() {
  if (typeof window === 'undefined') return;
  try {
    const storedEvents = await storage.getAll<CalendarEvent>(STORE_NAME);
    calendarEvents.set(storedEvents.sort((a, b) => a.start - b.start));
  } catch (error) {
    console.error("Failed to initialize calendar store:", error);
    calendarEvents.set([]);
  }
}

/**
 * Creates a new event, saves it, and adds it to the store.
 * @param {Omit<CalendarEvent, 'id' | 'createdAt' | 'updatedAt'>} eventData - The data for the new event.
 */
export async function addEvent(eventData: Omit<CalendarEvent, 'id' | 'createdAt' | 'updatedAt'>) {
  const newEvent: CalendarEvent = {
    ...eventData,
    id: uuidv4(),
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  await storage.set(STORE_NAME, newEvent);
  calendarEvents.update(allEvents => [...allEvents, newEvent].sort((a, b) => a.start - b.start));
}

/**
 * Updates an existing calendar event.
 * @param {string} id - The ID of the event to update.
 * @param {Partial<Omit<CalendarEvent, 'id'>>} eventData - The new data for the event.
 */
export async function updateEvent(id: string, eventData: Partial<Omit<CalendarEvent, 'id'>>) {
  calendarEvents.update(allEvents => {
    const eventIndex = allEvents.findIndex(e => e.id === id);
    if (eventIndex === -1) {
      console.warn(`Calendar event with id ${id} not found for update.`);
      return allEvents;
    }

    const updatedEvent = { ...allEvents[eventIndex], ...eventData, updatedAt: Date.now() };
    storage.set(STORE_NAME, updatedEvent);

    const newEvents = [...allEvents];
    newEvents[eventIndex] = updatedEvent;
    return newEvents.sort((a, b) => a.start - b.start);
  });
}

/**
 * Deletes an event from storage and the store.
 * @param {string} id - The ID of the event to delete.
 */
export async function deleteEvent(id: string) {
  await storage.del(STORE_NAME, id);
  calendarEvents.update(allEvents => allEvents.filter(e => e.id !== id));
}
