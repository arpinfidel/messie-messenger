export interface TimelineItem {
  id: string;
  type: 'matrix' | 'todo' | 'email' | 'calendar' | 'Message' | 'Call' | 'chat' | 'todo';
  title: string;
  description?: string;
  avatarUrl?: string; // optional HTTP avatar for the item
  content?: string;
  timestamp: number;
  unreadCount?: number;
  completed?: boolean;
  dueDate?: number;
  position?: string;
  listId?: string;
}
