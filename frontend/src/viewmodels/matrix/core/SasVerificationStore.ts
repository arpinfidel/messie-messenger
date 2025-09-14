import { writable } from 'svelte/store';

export interface SasVerificationData {
  emoji: [string, string][];
  confirm: () => Promise<void>;
  cancel: () => void;
  waiting: boolean;
}

export const sasVerificationStore = writable<SasVerificationData | null>(null);
