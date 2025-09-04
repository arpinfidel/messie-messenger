import type { LiteRoom, LiteMessage, LiteMember } from './types';

/**
 * Public interface for the lightweight Matrix client.
 * Internals can swap between mock and real implementations
 * without affecting consumers.
 */
export interface MatrixLiteClient {
  login(username: string, password: string): Promise<void>;
  logout(): Promise<void>;
  listRooms(): Promise<LiteRoom[]>;
  getRoomMessages(roomId: string, limit?: number): Promise<LiteMessage[]>;
  sendMessage(roomId: string, content: string): Promise<LiteMessage>;
  getRoomMembers(roomId: string): Promise<LiteMember[]>;
}

/**
 * Create a MatrixLiteClient backed by in-memory mock data.
 * Every call prints a `[compat-mock]` warning to highlight
 * that fake data is being used.
 */
export function createMockClient(): MatrixLiteClient {
  console.warn('[compat-mock] Using mock Matrix Lite client');

  const userId = '@alice:example.org';
  const rooms: Array<{
    room: LiteRoom;
    messages: LiteMessage[];
    members: LiteMember[];
  }> = [
    {
      room: { id: '!room1:example.org', name: 'General' },
      messages: [
        {
          id: '$msg1',
          roomId: '!room1:example.org',
          sender: '@alice:example.org',
          content: 'Welcome to the General room',
          timestamp: Date.now() - 60000,
        },
        {
          id: '$msg2',
          roomId: '!room1:example.org',
          sender: '@bob:example.org',
          content: 'Hello everyone!',
          timestamp: Date.now() - 30000,
        },
      ],
      members: [
        { userId: '@alice:example.org', displayName: 'Alice' },
        { userId: '@bob:example.org', displayName: 'Bob' },
      ],
    },
    {
      room: { id: '!room2:example.org', name: 'Random' },
      messages: [
        {
          id: '$msg3',
          roomId: '!room2:example.org',
          sender: '@carol:example.org',
          content: 'Random chatter goes here',
          timestamp: Date.now() - 50000,
        },
      ],
      members: [
        { userId: '@carol:example.org', displayName: 'Carol' },
        { userId: '@dave:example.org', displayName: 'Dave' },
      ],
    },
  ];

  return {
    async login(_username: string, _password: string): Promise<void> {
      console.warn('[compat-mock] login() called');
    },
    async logout(): Promise<void> {
      console.warn('[compat-mock] logout() called');
    },
    async listRooms(): Promise<LiteRoom[]> {
      console.warn('[compat-mock] listRooms() called');
      return rooms.map((r) => r.room);
    },
    async getRoomMessages(roomId: string): Promise<LiteMessage[]> {
      console.warn('[compat-mock] getRoomMessages() called');
      return rooms.find((r) => r.room.id === roomId)?.messages ?? [];
    },
    async sendMessage(roomId: string, content: string): Promise<LiteMessage> {
      console.warn('[compat-mock] sendMessage() called');
      const room = rooms.find((r) => r.room.id === roomId);
      if (!room) throw new Error('Room not found');
      const msg: LiteMessage = {
        id: `$msg${Math.random().toString(36).slice(2)}`,
        roomId,
        sender: userId,
        content,
        timestamp: Date.now(),
      };
      room.messages.push(msg);
      return msg;
    },
    async getRoomMembers(roomId: string): Promise<LiteMember[]> {
      console.warn('[compat-mock] getRoomMembers() called');
      return rooms.find((r) => r.room.id === roomId)?.members ?? [];
    },
  };
}
