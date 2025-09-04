import type { Blob as NodeBlob } from 'buffer';

// Simple in-memory store for mock data
interface Session {
  access_token: string;
  user_id: string;
  device_id: string;
  homeserverUrl: string;
}

interface RoomStateEvent {
  type: string;
  content: any;
}

interface RoomMessage {
  event_id: string;
  sender: string;
  content: any;
  origin_server_ts: number;
}

interface RoomMember {
  user_id: string;
  displayname?: string;
  avatar_url?: string;
}

let currentSession: Session | null = null;

const fakeRooms = [
  { room_id: '!room1:example.org', name: 'Test Room 1' },
  { room_id: '!room2:example.org', name: 'Test Room 2' },
];

const fakeStates: Record<string, RoomStateEvent[]> = {
  '!room1:example.org': [
    { type: 'm.room.name', content: { name: 'Test Room 1' } },
    { type: 'm.room.topic', content: { topic: 'Welcome to room 1' } },
  ],
  '!room2:example.org': [
    { type: 'm.room.name', content: { name: 'Test Room 2' } },
    { type: 'm.room.topic', content: { topic: 'Welcome to room 2' } },
  ],
};

const fakeMembers: Record<string, RoomMember[]> = {
  '!room1:example.org': [
    { user_id: '@alice:example.org', displayname: 'Alice' },
    { user_id: '@bob:example.org', displayname: 'Bob' },
  ],
  '!room2:example.org': [{ user_id: '@carol:example.org', displayname: 'Carol' }],
};

const fakeEvents: Record<string, RoomMessage[]> = {
  '!room1:example.org': [
    {
      event_id: '$evt1',
      sender: '@alice:example.org',
      content: { body: 'Hello from room1', msgtype: 'm.text' },
      origin_server_ts: Date.now() - 5000,
    },
    {
      event_id: '$evt2',
      sender: '@bob:example.org',
      content: { body: 'Hi Alice!', msgtype: 'm.text' },
      origin_server_ts: Date.now() - 2000,
    },
  ],
  '!room2:example.org': [
    {
      event_id: '$evt3',
      sender: '@carol:example.org',
      content: { body: 'Room2 says hi', msgtype: 'm.text' },
      origin_server_ts: Date.now() - 1000,
    },
  ],
};

function warn(method: string) {
  console.warn(`[compat-mock] ${method} is mocked`);
}

export async function loginWithPassword(homeserverUrl: string, username: string, password: string) {
  const res = await fetch(`${homeserverUrl}/_matrix/client/v3/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      type: 'm.login.password',
      identifier: { type: 'm.id.user', user: username },
      password,
    }),
  });
  if (!res.ok) {
    throw new Error(`Login failed with status ${res.status}`);
  }
  const data = await res.json();
  currentSession = {
    access_token: data.access_token,
    user_id: data.user_id,
    device_id: data.device_id,
    homeserverUrl,
  };
  return currentSession;
}

export async function logout() {
  if (!currentSession) return;
  await fetch(`${currentSession.homeserverUrl}/_matrix/client/v3/logout`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${currentSession.access_token}` },
  });
  currentSession = null;
}

export function hasSession(): boolean {
  return currentSession !== null;
}

export function setSession(session: Session) {
  currentSession = session;
}

export async function listJoinedRooms() {
  warn('listJoinedRooms');
  return fakeRooms.map((r) => r.room_id);
}

export async function getRoomState(roomId: string) {
  warn('getRoomState');
  return fakeStates[roomId] || [];
}

export async function getRoomMembers(roomId: string) {
  warn('getRoomMembers');
  return fakeMembers[roomId] || [];
}

export async function getMessages(roomId: string, from?: string, dir: 'b' | 'f' = 'b', limit = 20) {
  warn('getMessages');
  const events = fakeEvents[roomId] || [];
  let start = from ? parseInt(from, 10) : events.length;
  if (Number.isNaN(start)) start = events.length;
  const end = Math.max(0, dir === 'b' ? start - limit : start + limit);
  const slice = dir === 'b' ? events.slice(end, start) : events.slice(start, end);
  const next =
    dir === 'b' ? (end > 0 ? String(end) : null) : end < events.length ? String(end) : null;
  return { chunk: slice, nextBatch: next };
}

export async function sendMessage(roomId: string, content: any) {
  warn('sendMessage');
  const arr = fakeEvents[roomId] || (fakeEvents[roomId] = []);
  const evt: RoomMessage = {
    event_id: `$fake${Date.now()}`,
    sender: currentSession?.user_id || '@mock:example.org',
    content,
    origin_server_ts: Date.now(),
  };
  arr.push(evt);
  return evt;
}

export async function uploadMedia(data: Blob | ArrayBuffer | NodeBlob, contentType: string) {
  warn('uploadMedia');
  return 'mxc://mock/123';
}

export function mxcToHttp(mxcUrl: string) {
  warn('mxcToHttp');
  return `https://example.org/_matrix/media/r0/download/${mxcUrl.replace('mxc://', '')}`;
}

export function startMiniSync() {
  warn('startMiniSync');
}

export function stopMiniSync() {
  warn('stopMiniSync');
}

export function onToDevice(handler: (evts: any[]) => void) {
  warn('onToDevice');
  // no-op
}

export async function initCrypto() {
  warn('initCrypto');
}

export async function decryptEvent(evt: any) {
  warn('decryptEvent');
  return evt;
}

export async function encryptEvent(roomId: string, type: string, plain: any) {
  warn('encryptEvent');
  return { type, content: plain };
}
