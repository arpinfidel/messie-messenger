import { writable, type Readable } from 'svelte/store';
import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import type { TimelineItem } from '@/models/shared/TimelineItem';

export class EmailViewModel implements IModuleViewModel {
    private timelineItems = writable<TimelineItem[]>([]);

    async initialize(): Promise<void> {
        console.log('[EmailViewModel] Initialization started.');
        // Simulate a 20-second loading delay
        await new Promise(resolve => setTimeout(resolve, 30000));
        console.log('[EmailViewModel] Initialization completed.');
        
        // Populate with dummy TimelineItem objects
        const dummyItems: TimelineItem[] = [
            {
                id: 'email-1',
                title: 'Dummy Email 1',
                description: 'This is a dummy email item for testing.',
                timestamp: new Date().getTime(),
                type: 'email'
            },
            {
                id: 'email-2',
                title: 'Dummy Email 2',
                description: 'Another dummy email for demonstration.',
                timestamp: new Date(Date.now() - 3600000).getTime(), // 1 hour ago
                type: 'email'
            },
            {
                id: 'email-3',
                title: 'Dummy Email 3',
                description: 'A third dummy email.',
                timestamp: new Date(Date.now() - 7200000).getTime(), // 2 hours ago
                type: 'email'
            }
        ];
        this.timelineItems.set(dummyItems);
    }

    getTimelineItems(): Readable<TimelineItem[]> {
        return this.timelineItems;
    }

    getModuleName(): string {
        return "Email";
    }

    getSettingsComponent(): null {
        return null;
    }
}