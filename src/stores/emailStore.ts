import { writable } from 'svelte/store';
import * as storage from '../services/storage';
import * as emailService from '../services/emailService';

// --- Types ---
export interface Email extends emailService.EmailData {
  read: boolean;
  starred: boolean;
}

// --- Store ---
export const emails = writable<Email[]>([]);
const STORE_NAME = 'emails';

// --- Actions ---

/**
 * Loads emails from IndexedDB and then checks for new emails from the server.
 */
export async function initEmailStore() {
  if (typeof window === 'undefined') return;
  try {
    const storedEmails = await storage.getAll<Email>(STORE_NAME);
    emails.set(storedEmails.sort((a, b) => b.date - a.date));
    // After initializing, check for new emails from the server
    await refreshEmails();
  } catch (error) {
    console.error("Failed to initialize email store:", error);
    emails.set([]);
  }
}

/**
 * Fetches new emails from the service and adds them to the store and storage.
 */
export async function refreshEmails() {
  try {
    const newEmailsData = await emailService.fetchNewEmails();
    if (newEmailsData.length === 0) {
      return;
    }

    const newEmails: Email[] = newEmailsData.map(e => ({
      ...e,
      read: false,
      starred: false,
    }));

    for (const email of newEmails) {
      await storage.set(STORE_NAME, email);
    }

    emails.update(allEmails =>
      [...newEmails, ...allEmails].sort((a, b) => b.date - a.date)
    );
  } catch (error) {
    console.error("Failed to refresh emails:", error);
  }
}

/**
 * Marks an email as read or unread.
 * @param {string} id - The ID of the email to update.
 * @param {boolean} read - The new read status.
 */
export async function markAsRead(id: string, read: boolean) {
  emails.update(allEmails => {
    const emailIndex = allEmails.findIndex(e => e.id === id);
    if (emailIndex === -1) return allEmails;

    const updatedEmail = { ...allEmails[emailIndex], read };
    storage.set(STORE_NAME, updatedEmail);

    const newEmails = [...allEmails];
    newEmails[emailIndex] = updatedEmail;
    return newEmails;
  });
}

/**
 * Toggles the "starred" status of an email.
 * @param {string} id - The ID of the email to toggle.
 */
export async function toggleStarred(id: string) {
  emails.update(allEmails => {
    const emailIndex = allEmails.findIndex(e => e.id === id);
    if (emailIndex === -1) return allEmails;

    const updatedEmail = { ...allEmails[emailIndex], starred: !allEmails[emailIndex].starred };
    storage.set(STORE_NAME, updatedEmail);

    const newEmails = [...allEmails];
    newEmails[emailIndex] = updatedEmail;
    return newEmails;
  });
}

/**
 * Deletes an email from storage and the store.
 * @param {string} id - The ID of the email to delete.
 */
export async function deleteEmail(id: string) {
  await storage.del(STORE_NAME, id);
  emails.update(allEmails => allEmails.filter(e => e.id !== id));
}
