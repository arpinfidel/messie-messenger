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
  return httpRequest(homeserverUrl, '/_matrix/client/v3/keys/claim', {
    method: 'POST',
    accessToken,
    body,
  });
}

