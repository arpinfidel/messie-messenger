import { httpRequest } from '../http/base';

/**
 * Fetch a lightweight /sync to obtain a valid prev_batch token for a room.
 * Some homeservers do not support `from=END` on /messages; prev_batch avoids that.
 */
export async function getRoomPrevBatchToken(
  homeserverUrl: string,
  accessToken: string,
  roomId: string
): Promise<string | null> {
  const filter = {
    room: {
      timeline: { limit: 1, types: ['m.room.message', 'm.room.encrypted'] },
      include_leave: true,
    },
    presence: { not_types: ['*'] },
    account_data: { not_types: ['*'] },
  } as any;
  const qs = new URLSearchParams({ timeout: '0', filter: JSON.stringify(filter) });
  const path = `/_matrix/client/v3/sync?${qs.toString()}`;
  const res = await httpRequest(homeserverUrl, path, { accessToken });

  const join = res?.rooms?.join;
  if (join && typeof join === 'object') {
    const room = join[roomId];
    const token = room?.timeline?.prev_batch;
    if (typeof token === 'string' && token.length > 0) return token;
  }
  return null;
}

