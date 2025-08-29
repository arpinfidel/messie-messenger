export interface TimelineItem {
  id: string;
  type: 'matrix' | 'todo' | 'email' | 'calendar' | 'Message' | 'Call' | 'chat' | 'todo';
  title: string;
  description?: string;
  content?: string;
  timestamp: number;
  completed?: boolean;
  dueDate?: number;
  position?: string;
  listId?: string;
}
