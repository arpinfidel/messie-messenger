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

export async function uploadDeviceSigningKeys(
  homeserverUrl: string,
  accessToken: string,
  body: any
): Promise<any> {
  // Try stable path first; some servers might require unstable
  try {
    return await httpRequest(homeserverUrl, '/_matrix/client/v3/keys/device_signing/upload', {
      method: 'POST',
      accessToken,
      body,
    });
  } catch (e) {
    // Fallback to unstable
    return httpRequest(homeserverUrl, '/_matrix/client/unstable/keys/device_signing/upload', {
      method: 'POST',
      accessToken,
      body,
    });
  }
}
