import { httpRequest } from '../http/base';

export async function getDefaultSecretStorageKey(
  homeserverUrl: string,
  accessToken: string
): Promise<{ key?: string } | null> {
  try {
    return await httpRequest(
      homeserverUrl,
      '/_matrix/client/v3/secret_storage/default_key',
      { accessToken }
    );
  } catch (e) {
    // fallback to r0 for older servers
    try {
      return await httpRequest(
        homeserverUrl,
        '/_matrix/client/r0/secret_storage/default_key',
        { accessToken }
      );
    } catch (e2) {
      console.warn('[ssss] getDefaultSecretStorageKey failed', e2);
      return null;
    }
  }
}

export async function getSecretStorageKeyInfo(
  homeserverUrl: string,
  accessToken: string,
  keyId: string
): Promise<any | null> {
  try {
    return await httpRequest(
      homeserverUrl,
      `/_matrix/client/v3/secret_storage/key/${encodeURIComponent(keyId)}`,
      { accessToken }
    );
  } catch (e) {
    try {
      return await httpRequest(
        homeserverUrl,
        `/_matrix/client/r0/secret_storage/key/${encodeURIComponent(keyId)}`,
        { accessToken }
      );
    } catch (e2) {
      console.warn('[ssss] getSecretStorageKeyInfo failed', e2);
      return null;
    }
  }
}

export async function getSecret(
  homeserverUrl: string,
  accessToken: string,
  name: string
): Promise<any | null> {
  try {
    return await httpRequest(
      homeserverUrl,
      `/_matrix/client/v3/secret_storage/secret/${encodeURIComponent(name)}`,
      { accessToken }
    );
  } catch (e) {
    try {
      return await httpRequest(
        homeserverUrl,
        `/_matrix/client/r0/secret_storage/secret/${encodeURIComponent(name)}`,
        { accessToken }
      );
    } catch (e2) {
      console.warn('[ssss] getSecret failed', e2);
      return null;
    }
  }
}

export async function fetchSSSSViaSync(
  homeserverUrl: string,
  accessToken: string
): Promise<{ defaultKeyId?: string; encryptedByKeyId?: Record<string, any> } | null> {
  try {
    const filter: any = {
      room: { not_types: ['*'] },
      presence: { not_types: ['*'] },
      account_data: {
        types: ['m.secret_storage.default_key', 'm.megolm_backup.v1'],
      },
    };
    const qs = new URLSearchParams({ timeout: '0', filter: JSON.stringify(filter) });
    const path = `/_matrix/client/v3/sync?${qs.toString()}`;
    const res = await httpRequest(homeserverUrl, path, { accessToken });
    const events: any[] = res?.account_data?.events || [];
    let defaultKeyId: string | undefined;
    let encryptedByKeyId: Record<string, any> | undefined;
    for (const ev of events) {
      if (!ev || typeof ev !== 'object') continue;
      if (ev.type === 'm.secret_storage.default_key') {
        const key = ev.content?.key || ev.content?.default || ev.content?.key_id;
        if (typeof key === 'string') defaultKeyId = key;
      }
      if (ev.type === 'm.megolm_backup.v1') {
        const enc = ev.content?.encrypted;
        if (enc && typeof enc === 'object') encryptedByKeyId = enc as Record<string, any>;
      }
    }
    return { defaultKeyId, encryptedByKeyId };
  } catch (e) {
    console.warn('[ssss] fetchSSSSViaSync failed', e);
    return null;
  }
}

export async function getDefaultSecretStorageKeyFromAccountData(
  homeserverUrl: string,
  accessToken: string,
  userId: string
): Promise<{ key?: string } | null> {
  // Account Data event: m.secret_storage.default_key
  try {
    const path = `/_matrix/client/v3/user/${encodeURIComponent(
      userId
    )}/account_data/m.secret_storage.default_key`;
    return await httpRequest(homeserverUrl, path, { accessToken });
  } catch (e) {
    try {
      const path = `/_matrix/client/r0/user/${encodeURIComponent(
        userId
      )}/account_data/m.secret_storage.default_key`;
      return await httpRequest(homeserverUrl, path, { accessToken });
    } catch (e2) {
      console.warn('[ssss] getDefaultSecretStorageKeyFromAccountData failed', e2);
      return null;
    }
  }
}

export async function getSecretFromAccountData(
  homeserverUrl: string,
  accessToken: string,
  userId: string,
  name: string
): Promise<any | null> {
  // Secrets are stored directly under their name (e.g., 'm.megolm_backup.v1')
  const type = name;
  try {
    const path = `/_matrix/client/v3/user/${encodeURIComponent(userId)}/account_data/${encodeURIComponent(
      type
    )}`;
    return await httpRequest(homeserverUrl, path, { accessToken });
  } catch (e) {
    try {
      const path = `/_matrix/client/r0/user/${encodeURIComponent(userId)}/account_data/${encodeURIComponent(
        type
      )}`;
      return await httpRequest(homeserverUrl, path, { accessToken });
    } catch (e2) {
      console.warn('[ssss] getSecretFromAccountData failed', e2);
      return null;
    }
  }
}
