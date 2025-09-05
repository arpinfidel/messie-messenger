import { httpRequest } from '../http/base';
import type { LiteSession } from '../runtime/session';

interface LoginResponse {
  access_token: string;
  user_id: string;
  device_id: string;
}

export async function login(homeserverUrl: string, username: string, password: string): Promise<LiteSession> {
  const body = {
    type: 'm.login.password',
    identifier: { type: 'm.id.user', user: username },
    password,
  };
  const res: LoginResponse = await httpRequest(homeserverUrl, '/_matrix/client/v3/login', {
    method: 'POST',
    body,
  });
  return {
    homeserverUrl,
    accessToken: res.access_token,
    userId: res.user_id,
    deviceId: res.device_id,
  };
}

export async function logout(homeserverUrl: string, accessToken: string): Promise<void> {
  await httpRequest(homeserverUrl, '/_matrix/client/v3/logout', {
    method: 'POST',
    accessToken,
  });
}
