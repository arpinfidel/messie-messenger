import { writable, type Writable } from 'svelte/store';

export interface DeveloperSettingsState {
  enableEruda: boolean;
  showBuildTimestamp: boolean;
}

const STORAGE_KEY = 'developerSettings';
const defaultState: DeveloperSettingsState = {
  enableEruda: false,
  showBuildTimestamp: false,
};

declare global {
  // eslint-disable-next-line @typescript-eslint/consistent-type-imports
  interface Window {
    eruda?: {
      init: () => void;
      destroy: () => void;
      // Some versions expose hide/show; keep destroy for cleanup.
    };
  }
}

function loadInitialState(): DeveloperSettingsState {
  if (typeof window === 'undefined') {
    return { ...defaultState };
  }

  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...defaultState };
    const parsed = JSON.parse(raw) as Partial<DeveloperSettingsState> | null;
    if (!parsed) return { ...defaultState };
    return {
      ...defaultState,
      ...parsed,
      enableEruda: Boolean(parsed.enableEruda),
      showBuildTimestamp: Boolean(parsed.showBuildTimestamp),
    };
  } catch (err) {
    console.warn('[DeveloperSettings] Failed to load settings, using defaults', err);
    return { ...defaultState };
  }
}

function persistState(state: DeveloperSettingsState) {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (err) {
    console.warn('[DeveloperSettings] Failed to persist settings', err);
  }
}

let erudaScriptPromise: Promise<unknown> | null = null;
let erudaEnabled = false;
let latestState: DeveloperSettingsState = loadInitialState();

function loadErudaScript(): Promise<unknown> {
  if (typeof window === 'undefined') {
    return Promise.resolve();
  }

  if (window.eruda) {
    return Promise.resolve(window.eruda);
  }

  if (!erudaScriptPromise) {
    erudaScriptPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/eruda';
      script.async = true;
      script.onload = () => resolve(window.eruda);
      script.onerror = (event) => reject(event);
      document.body.appendChild(script);
    }).catch((err) => {
      console.warn('[DeveloperSettings] Failed to load eruda script', err);
      erudaScriptPromise = null;
      throw err;
    });
  }

  return erudaScriptPromise;
}

async function enableEruda(): Promise<void> {
  if (typeof window === 'undefined') return;
  if (erudaEnabled) return;

  try {
    const requestedAt = latestState;
    await loadErudaScript();
    if (!requestedAt.enableEruda || !latestState.enableEruda) {
      // Preference toggled off while script was loading; do nothing.
      return;
    }
    window.eruda?.init();
    erudaEnabled = true;
  } catch (err) {
    console.warn('[DeveloperSettings] Unable to initialise eruda', err);
  }
}

function disableEruda(): void {
  if (typeof window === 'undefined') return;
  if (!erudaEnabled) return;
  try {
    window.eruda?.destroy();
  } catch (err) {
    console.warn('[DeveloperSettings] Failed to destroy eruda', err);
  } finally {
    erudaEnabled = false;
  }
}

async function syncEruda(state: DeveloperSettingsState): Promise<void> {
  if (state.enableEruda) {
    await enableEruda();
  } else {
    disableEruda();
  }
}

const developerSettingsStore: Writable<DeveloperSettingsState> = writable(latestState);

if (typeof window !== 'undefined') {
  developerSettingsStore.subscribe((state) => {
    latestState = state;
    persistState(state);
    void syncEruda(state);
  });
}

export const developerSettings = developerSettingsStore;

export function setErudaEnabled(enabled: boolean): void {
  developerSettingsStore.update((current) => {
    if (current.enableEruda === enabled) return current;
    return { ...current, enableEruda: enabled };
  });
}

export function setBuildTimestampVisibility(visible: boolean): void {
  developerSettingsStore.update((current) => {
    if (current.showBuildTimestamp === visible) return current;
    return { ...current, showBuildTimestamp: visible };
  });
}
