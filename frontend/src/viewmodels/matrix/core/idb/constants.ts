// Shared IndexedDB constants and shared record types

export const DB_NAME = 'mx-app-store';
export const DB_VERSION = 4;

export const STORES = {
  ROOMS: 'rooms',
  EVENTS: 'events',
  TOKENS: 'tokens',
  META: 'meta',
  USERS: 'users',
  MEDIA: 'media',
  MEMBERS: 'members',
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
}

export type TokenRecord = { roomId: string; backward: string | null };

export type MetaRecord = { key: string; value: any };

export interface DbMember {
  key: string; // `${roomId}|${userId}`
  roomId: string;
  userId: string;
  displayName?: string;
  avatarUrl?: string; // MXC URL
  membership?: string; // 'join', 'leave', etc.
}
