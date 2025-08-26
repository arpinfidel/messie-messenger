export interface TimelineItem {
  id: number;
  type: 'email' | 'calendar' | 'chat';
  content: string;
  timestamp: string;
  sender?: string;
  subject?: string;
  date?: string;
  time?: string;
  participants?: string[];
}

export async function fetchTimelineData(): Promise<TimelineItem[]> {
  return new Promise(resolve => {
    setTimeout(() => {
      resolve([
        { id: 1, type: 'chat', content: 'Hey, how are you?', timestamp: '10:00 AM', sender: 'Alice' },
        { id: 2, type: 'email', content: 'Meeting notes for Q3', timestamp: '10:35 AM', subject: 'Q3 Meeting', sender: 'Bob' },
        { id: 3, type: 'calendar', content: 'Team Sync', timestamp: '11:00 AM', date: '2025-08-26', time: '11:00 AM', participants: ['Alice', 'Bob', 'Charlie'] },
        { id: 4, type: 'chat', content: 'I am good, thanks!', timestamp: '10:01 AM', sender: 'Bob' },
        { id: 5, type: 'email', content: 'Follow up on project X', timestamp: '11:15 AM', subject: 'Project X', sender: 'Charlie' },
      ]);
    }, 500);
  });
}