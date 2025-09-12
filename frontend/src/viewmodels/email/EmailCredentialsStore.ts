import { writable } from 'svelte/store';

export interface EmailCredentials {
  host: string;
  port: number;
  email: string;
  appPassword: string;
}

export const emailCredentials = writable<EmailCredentials | null>(null);
