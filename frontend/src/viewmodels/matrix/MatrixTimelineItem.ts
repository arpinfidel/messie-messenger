import type { TimelineItem } from '@/models/shared/TimelineItem';

/**
 * @interface IMatrixTimelineItem
 * @description Represents a Matrix room or event as a unified timeline item.
 */
export interface IMatrixTimelineItem extends TimelineItem {
  id: string;
  type: 'matrix';
  title: string;
  description?: string;
  avatarUrl?: string;
  timestamp: number; // Changed to number
  rawData?: object;
  sender?: string; // Add sender property
  unreadCount?: number;
}

/**
 * @class MatrixTimelineItem
 * @description Implements the IMatrixTimelineItem interface.
 */
export class MatrixTimelineItem implements IMatrixTimelineItem {
  id: string;
  type: 'matrix';
  title: string;
  description: string;
  avatarUrl?: string;
  timestamp: number; // Changed to number
  rawData: object;
  sender: string; // Add sender property
  unreadCount?: number;

  constructor({
    id,
    type = 'matrix',
    title,
    description = '',
    avatarUrl,
    timestamp,
    rawData = {},
    sender = '',
    unreadCount,
  }: IMatrixTimelineItem) {
    if (!id || !title) throw new Error('MatrixTimelineItem requires id and title.');
    if (
      timestamp === undefined ||
      timestamp === null ||
      typeof timestamp !== 'number' ||
      Number.isNaN(timestamp)
    ) {
      throw new Error('MatrixTimelineItem requires a numeric timestamp.');
    }

    this.id = id;
    this.type = type;
    this.title = title;
    this.description = description;
    this.avatarUrl = avatarUrl;
    this.timestamp = timestamp;
    this.rawData = rawData;
    this.sender = sender; // Initialize sender
    this.unreadCount = unreadCount;
  }
}
