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
  timestamp: number; // Changed to number
  rawData?: object;
  sender?: string; // Add sender property
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
  timestamp: number; // Changed to number
  rawData: object;
  sender: string; // Add sender property

  constructor({
    id,
    type = 'matrix',
    title,
    description = '',
    timestamp,
    rawData = {},
    sender = '',
  }: IMatrixTimelineItem) {
    if (!id || !title || !timestamp) {
      throw new Error('MatrixTimelineItem requires id, title, and timestamp.');
    }

    this.id = id;
    this.type = type;
    this.title = title;
    this.description = description;
    this.timestamp = timestamp;
    this.rawData = rawData;
    this.sender = sender; // Initialize sender
  }
}
