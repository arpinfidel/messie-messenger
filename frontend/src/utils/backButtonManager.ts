import { App } from '@capacitor/app';
import type { BackButtonListenerEvent } from '@capacitor/app';
import { Capacitor } from '@capacitor/core';
import type { PluginListenerHandle } from '@capacitor/core';

type BackButtonHandler = () => boolean | void;

function isNativePlatform(): boolean {
  try {
    if (typeof Capacitor.isNativePlatform === 'function') {
      return Capacitor.isNativePlatform();
    }
    const platform = Capacitor.getPlatform?.();
    return platform !== undefined && platform !== 'web';
  } catch (error) {
    console.warn('[BackButtonManager] Failed to detect platform', error);
    return false;
  }
}

class BackButtonManager {
  private handlers: BackButtonHandler[] = [];
  private listener: PluginListenerHandle | null = null;
  private readonly native = isNativePlatform();

  register(handler: BackButtonHandler): () => void {
    this.handlers.push(handler);
    void this.ensureListener();
    return () => {
      const index = this.handlers.lastIndexOf(handler);
      if (index !== -1) {
        this.handlers.splice(index, 1);
      }
    };
  }

  private async ensureListener(): Promise<void> {
    if (!this.native || this.listener) {
      return;
    }

    try {
      this.listener = await App.addListener('backButton', (event: BackButtonListenerEvent) => {
        for (let i = this.handlers.length - 1; i >= 0; i -= 1) {
          const handled = this.handlers[i]();
          if (handled !== false) {
            return;
          }
        }

        if (event.canGoBack) {
          window.history.back();
        } else {
          void App.exitApp();
        }
      });
    } catch (error) {
      console.warn('[BackButtonManager] Failed to attach backButton listener', error);
      this.listener = null;
    }
  }
}

const manager = new BackButtonManager();

export function registerBackButtonHandler(handler: BackButtonHandler): () => void {
  return manager.register(handler);
}
