export interface TimelineItem {
  id: string;
  type: 'matrix' | 'todo' | 'email' | 'calendar' | 'Message' | 'Call' | 'chat' | 'todo';
  title: string;
  description?: string;
  avatarUrl?: string; // optional HTTP avatar for the item
  content?: string;
  /**
   * Optional raw data backing this item. Used primarily by Matrix items but
   * available for other modules if needed.
   */
  rawData?: object;
  /** Optional sender or author of the item. */
  sender?: string;
  timestamp: number;
  unreadCount?: number;
  completed?: boolean;
  dueDate?: number;
  position?: string;
  listId?: string;
}
