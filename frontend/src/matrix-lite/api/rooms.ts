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
