import { httpRequest } from '../http/base';

export interface MessagesResponse {
  chunk: any[];
  start: string;
  end?: string;
}

export async function roomMessages(
  homeserverUrl: string,
  accessToken: string,
  roomId: string,
  fromToken?: string,
  limit = 20
): Promise<MessagesResponse> {
  const params = new URLSearchParams({ dir: 'b', limit: String(limit) });
  params.set('from', fromToken || 'END');
  const path = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/messages?${params.toString()}`;
  return httpRequest(homeserverUrl, path, { accessToken });
}

export async function sendRoomMessage(
  homeserverUrl: string,
  accessToken: string,
  roomId: string,
  content: string
): Promise<string> {
  const txnId = Date.now().toString();
  const path = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/send/m.room.message/${txnId}`;
  const res = await httpRequest(homeserverUrl, path, {
    method: 'PUT',
    accessToken,
    body: { msgtype: 'm.text', body: content },
  });
  return res.event_id;
}

/**
 * Send an arbitrary room event.
 * Used for encrypted events where the event type is not m.room.message.
 */
export async function sendRoomEvent(
  homeserverUrl: string,
  accessToken: string,
  roomId: string,
  eventType: string,
  content: any
): Promise<string> {
  const txnId = Date.now().toString();
  const path = `/_matrix/client/v3/rooms/${encodeURIComponent(
    roomId
  )}/send/${encodeURIComponent(eventType)}/${txnId}`;
  const res = await httpRequest(homeserverUrl, path, {
    method: 'PUT',
    accessToken,
    body: content,
  });
  return res.event_id;
}
