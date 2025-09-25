import { Capacitor } from '@capacitor/core';
import {
  LocalNotifications,
  type LocalNotificationSchema,
  type PermissionStatus,
} from '@capacitor/local-notifications';

export interface INotificationService {
  requestPermission(): Promise<boolean>;
  notify(opts: {
    title: string;
    body?: string;
    icon?: string;
    onClick?: () => void;
  }): Promise<void>;
}

export class BrowserNotificationService implements INotificationService {
  async requestPermission(): Promise<boolean> {
    if (typeof window === 'undefined' || !('Notification' in window)) {
      return false;
    }
    if (Notification.permission === 'granted') return true;
    const perm = await Notification.requestPermission();
    return perm === 'granted';
  }

  async notify(opts: {
    title: string;
    body?: string;
    icon?: string;
    onClick?: () => void;
  }): Promise<void> {
    if (typeof window === 'undefined' || !('Notification' in window)) {
      return;
    }
    if (Notification.permission !== 'granted') {
      const granted = await this.requestPermission();
      if (!granted) return;
    }
    const icon = opts.icon || '/messie-logo.svg';
    const n = new Notification(opts.title, {
      body: opts.body,
      icon,
      // Provide a badge as well where supported (monochrome recommended; using logo for now)
      badge: icon,
    });
    if (opts.onClick) {
      n.onclick = () => {
        opts.onClick && opts.onClick();
        n.close();
      };
    }
  }
}

export class CapacitorNotificationService implements INotificationService {
  private static readonly MAX_NATIVE_NOTIFICATION_ID = 0x7fffffff;
  private nextId = CapacitorNotificationService.randomId();
  private clickListenerInitialized = false;
  private callbacks = new Map<number, () => void>();

  private static randomId(): number {
    // Android requires notification identifiers to fit into a signed 32-bit int.
    const value = Math.floor(
      Math.random() * CapacitorNotificationService.MAX_NATIVE_NOTIFICATION_ID,
    );
    return value > 0 ? value : 1;
  }

  private async ensureListener() {
    if (this.clickListenerInitialized) return;
    this.clickListenerInitialized = true;
    try {
      await LocalNotifications.addListener('localNotificationActionPerformed', (event) => {
        const notification = event?.notification as LocalNotificationSchema | undefined;
        const id = notification?.id;
        if (typeof id === 'number') {
          const cb = this.callbacks.get(id);
          if (cb) {
            this.callbacks.delete(id);
            try {
              cb();
            } catch (err) {
              console.warn('[CapacitorNotificationService] onClick handler failed', err);
            }
          }
        }
      });
    } catch (err) {
      console.warn('[CapacitorNotificationService] Failed to attach listener', err);
    }
  }

  private async ensurePermission(): Promise<boolean> {
    let status: PermissionStatus;
    try {
      status = await LocalNotifications.checkPermissions();
    } catch (err) {
      console.warn('[CapacitorNotificationService] checkPermissions failed', err);
      return false;
    }
    if (status.display === 'granted') {
      return true;
    }
    try {
      status = await LocalNotifications.requestPermissions();
    } catch (err) {
      console.warn('[CapacitorNotificationService] requestPermissions failed', err);
      return false;
    }
    return status.display === 'granted';
  }

  async requestPermission(): Promise<boolean> {
    return this.ensurePermission();
  }

  private reserveId(): number {
    const id = this.nextId;
    this.nextId =
      id >= CapacitorNotificationService.MAX_NATIVE_NOTIFICATION_ID ? 1 : id + 1;
    return id;
  }

  async notify(opts: {
    title: string;
    body?: string;
    icon?: string;
    onClick?: () => void;
  }): Promise<void> {
    const granted = await this.ensurePermission();
    if (!granted) return;

    await this.ensureListener();

    const id = this.reserveId();
    if (opts.onClick) {
      this.callbacks.set(id, opts.onClick);
    }

    try {
      await LocalNotifications.schedule({
        notifications: [
          {
            id,
            title: opts.title,
            body: opts.body || '',
            extra: opts.onClick ? { hasClickHandler: true } : undefined,
          },
        ],
      });
    } catch (err) {
      console.warn('[CapacitorNotificationService] schedule failed', err);
      this.callbacks.delete(id);
    }
  }
}

export function createNotificationService(): INotificationService {
  const nativeCheck = Capacitor?.isNativePlatform?.();
  const isNative =
    typeof nativeCheck === 'boolean'
      ? nativeCheck
      : (Capacitor?.getPlatform?.() ?? 'web') !== 'web';
  const hasPlugin = Capacitor?.isPluginAvailable?.('LocalNotifications') ?? false;
  if (isNative && hasPlugin) {
    return new CapacitorNotificationService();
  }
  return new BrowserNotificationService();
}
