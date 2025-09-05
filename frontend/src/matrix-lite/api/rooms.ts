import { httpRequest } from '../http/base';

/** Fetch the IDs of rooms the user has joined. */
export async function joinedRooms(homeserverUrl: string, accessToken: string): Promise<string[]> {
  const res = await httpRequest(homeserverUrl, '/_matrix/client/v3/joined_rooms', {
    accessToken,
  });
  return Array.isArray(res?.joined_rooms) ? res.joined_rooms : [];
}

/** Fetch the m.room.name state event for a room, if present. */
export async function getRoomName(
  homeserverUrl: string,
  accessToken: string,
  roomId: string
): Promise<string | undefined> {
  try {
    const path = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/state/m.room.name`;
    const res = await httpRequest(homeserverUrl, path, { accessToken });
    if (typeof res?.name === 'string') {
      return res.name;
    }
  } catch {
    // ignore missing state events
  }
  return undefined;
}

/**
 * Fetch room membership events and map to lightweight member records.
 * Only joined members are returned.
 */
export async function getRoomMembers(
  homeserverUrl: string,
  accessToken: string,
  roomId: string
): Promise<Array<{ userId: string; displayName: string; avatarUrl?: string; membership?: string }>> {
  const qs = new URLSearchParams({ membership: 'join' });
  const path = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/members?${qs.toString()}`;
  const res = await httpRequest(homeserverUrl, path, { accessToken });
  const events: any[] = Array.isArray(res?.chunk) ? res.chunk : [];
  const out: Array<{ userId: string; displayName: string; avatarUrl?: string; membership?: string }> = [];
  for (const ev of events) {
    if (ev?.type !== 'm.room.member') continue;
    const userId: string | undefined = typeof ev?.state_key === 'string' ? ev.state_key : undefined;
    if (!userId) continue;
    const content = ev?.content || {};
    const membership: string | undefined = typeof content?.membership === 'string' ? content.membership : undefined;
    if (membership && membership !== 'join') continue;
    const displayName: string = typeof content?.displayname === 'string' && content.displayname
      ? content.displayname
      : userId;
    const avatarUrl: string | undefined = typeof content?.avatar_url === 'string' && content.avatar_url
      ? content.avatar_url
      : undefined;
    out.push({ userId, displayName, avatarUrl, membership });
  }
  return out;
}
