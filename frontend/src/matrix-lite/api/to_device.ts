import { httpRequest } from '../http/base';

/** Send a to-device message batch */
export async function sendToDevice(
  homeserverUrl: string,
  accessToken: string,
  eventType: string,
  txnId: string,
  messages: Record<string, Record<string, any>>
): Promise<any> {
  const path = `/_matrix/client/v3/sendToDevice/${encodeURIComponent(eventType)}/${encodeURIComponent(txnId)}`;
  return httpRequest(homeserverUrl, path, {
    method: 'PUT',
    accessToken,
    body: { messages },
  });
}
