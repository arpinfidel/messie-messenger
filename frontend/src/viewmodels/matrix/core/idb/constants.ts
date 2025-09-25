// Shared IndexedDB constants and shared record types
import type { RepoEvent } from '../TimelineRepository';

export const DB_NAME = 'mx-app-store';
// Bump DB version whenever the schema changes. Version 6 removes legacy
// timeline/token stores now that sliding sync drives the timeline.
export const DB_VERSION = 7;

export const STORES = {
  ROOMS: 'rooms',
  META: 'meta',
  USERS: 'users',
  MEDIA: 'media',
  TIMELINE_EVENTS: 'timelineEvents',
} as const;

export interface DbUser {
  userId: string;
  displayName?: string;
  avatarMxcUrl?: string;
}

export interface DbRoom {
  id: string;
  name: string;
  latestTimestamp?: number;
  avatarMxcUrl?: string;
  unreadCount?: number;
  lastEvent?: RepoEvent | null;
}

export type MetaRecord = { key: string; value: any };

export interface DbMember {
  key: string; // `${roomId}|${userId}`
  roomId: string;
  userId: string;
  displayName?: string;
  avatarUrl?: string; // MXC URL
  membership?: string; // 'join', 'leave', etc.
  // Last known read receipt timestamp for this user in this room
  lastReadTs: number;
}

export interface DbTimelineEvent extends RepoEvent {}
