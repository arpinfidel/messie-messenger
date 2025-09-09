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
