import { writable, type Readable } from 'svelte/store';
import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import type { TimelineItem } from '@/models/shared/TimelineItem';

export class EmailViewModel implements IModuleViewModel {
  private static instance: EmailViewModel | null = null;
  private timelineItems = writable<TimelineItem[]>([]);

  static getInstance(): EmailViewModel {
    if (!EmailViewModel.instance) {
      EmailViewModel.instance = new EmailViewModel();
    }
    return EmailViewModel.instance;
  }

  async initialize(): Promise<void> {
    const now = Date.now();
    const items: TimelineItem[] = [
      {
        id: 'email-inbox',
        title: 'All Mail',
        description: 'All non-important emails',
        timestamp: now,
        type: 'email',
        unreadCount: 0,
      },
      {
        id: 'email-important',
        title: 'Important',
        description: 'Important emails',
        timestamp: now - 1,
        type: 'email',
        unreadCount: 0,
      },
      {
        id: 'email-thread-1',
        title: 'Sample thread 1',
        description: 'Thread subject',
        timestamp: now - 2,
        type: 'email',
        unreadCount: 0,
      },
      {
        id: 'email-thread-2',
        title: 'Sample thread 2',
        description: 'Thread subject',
        timestamp: now - 3,
        type: 'email',
        unreadCount: 0,
      },
    ];
    this.timelineItems.set(items);
  }

  getTimelineItems(): Readable<TimelineItem[]> {
    return this.timelineItems;
  }

  updateUnreadCount(itemId: string, count: number): void {
    this.timelineItems.update((items) =>
      items.map((it) => (it.id === itemId ? { ...it, unreadCount: count } : it))
    );
  }

  getModuleName(): string {
    return 'Email';
  }

  getSettingsComponent(): null {
    return null;
  }
}
