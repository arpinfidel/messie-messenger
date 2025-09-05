import { httpRequest } from '../http/base';

export async function uploadSignatures(
  homeserverUrl: string,
  accessToken: string,
  body: any
): Promise<any> {
  return httpRequest(homeserverUrl, '/_matrix/client/v3/keys/signatures/upload', {
    method: 'POST',
    accessToken,
    body,
  });
}

