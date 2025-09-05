import { httpRequest } from '../http/base';

export async function getBackupVersion(
  homeserverUrl: string,
  accessToken: string
): Promise<any> {
  return httpRequest(homeserverUrl, '/_matrix/client/v3/room_keys/version', {
    accessToken,
  });
}

export async function getBackupKeys(
  homeserverUrl: string,
  accessToken: string,
  version: string
): Promise<any> {
  const path = `/_matrix/client/v3/room_keys/keys?version=${encodeURIComponent(
    version
  )}`;
  return httpRequest(homeserverUrl, path, { accessToken });
}
