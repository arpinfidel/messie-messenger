export interface TimelineItem {
  id: string;
  type: 'matrix' | 'todo' | 'email' | 'calendar' | 'Message' | 'Call' | 'chat';
  title: string;
  description?: string;
  content?: string;
  timestamp: number;
}
