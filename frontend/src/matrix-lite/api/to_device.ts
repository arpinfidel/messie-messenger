import { httpRequest } from '../http/base';

/** Send to-device messages. */
export async function sendToDevice(
  homeserverUrl: string,
  accessToken: string,
  eventType: string,
  messages: Record<string, Record<string, any>>
): Promise<any> {
  try {
    const userCount = Object.keys(messages || {}).length;
    const deviceCount = Object.values(messages || {}).reduce(
      (acc, m) => acc + (m ? Object.keys(m).length : 0),
      0
    );
    const sampleUsers = Object.keys(messages || {}).slice(0, 3);
    console.log('[matrix-lite][debug] sendToDevice', { eventType, userCount, deviceCount, sampleUsers });
  } catch {}
  const txnId = Date.now().toString();
  const path = `/_matrix/client/v3/sendToDevice/${encodeURIComponent(eventType)}/${txnId}`;
  return httpRequest(homeserverUrl, path, {
    method: 'PUT',
    accessToken,
    body: { messages },
  });
}
