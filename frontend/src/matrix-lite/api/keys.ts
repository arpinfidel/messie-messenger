import { httpRequest } from '../http/base';

export async function keysUpload(
  homeserverUrl: string,
  accessToken: string,
  body: any
): Promise<any> {
  return httpRequest(homeserverUrl, '/_matrix/client/v3/keys/upload', {
    method: 'POST',
    accessToken,
    body,
  });
}

export async function keysQuery(
  homeserverUrl: string,
  accessToken: string,
  body: any
): Promise<any> {
  return httpRequest(homeserverUrl, '/_matrix/client/v3/keys/query', {
    method: 'POST',
    accessToken,
    body,
  });
}

export async function keysClaim(
  homeserverUrl: string,
  accessToken: string,
  body: any
): Promise<any> {
  try {
    const otk = body?.one_time_keys || {};
    const users = Object.keys(otk);
    const deviceTotal = Object.values(otk).reduce((acc: number, devs: any) => acc + (devs ? Object.keys(devs).length : 0), 0);
    console.log('[matrix-lite][debug] keysClaim request', { users: users.length, deviceTotal });
  } catch {}
  return httpRequest(homeserverUrl, '/_matrix/client/v3/keys/claim', {
    method: 'POST',
    accessToken,
    body,
  });
}
