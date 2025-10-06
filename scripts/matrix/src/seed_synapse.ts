#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { createHmac } from "crypto";
import fetch from "node-fetch";
import sdk, { type MatrixClient, createClient } from "matrix-js-sdk";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

type JSONObject = Record<string, unknown>;

type RateLimitInfo = {
  label: string;
  attempt: number;
  retries: number;
  delayMs: number;
  retryAfterMs?: number;
  error: unknown;
};

type RateLimitListener = (info: RateLimitInfo) => void;

type RetryOptions = {
  retries?: number;
  baseDelayMs?: number;
  onRateLimit?: RateLimitListener;
};

type SeederConfig = {
  serverUrl: string;
  serverName: string;
  sharedSecret: string;
  adminUsername: string;
  adminPassword: string;
  userUsername: string;
  userPassword: string;
  roomCount: number;
  deviceId: string;
  deviceName: string;
  stateDir: string;
  messageBody: string;
  adminDelayMs: number;
  concurrency: number;
};

type SecretStorageContext = {
  keyId?: string;
  privateKey: Uint8Array | null;
};

type RoomSeedState = {
  roomId: string;
  lastEventId: string;
};

type SeedStatePayload = {
  rooms: Record<string, RoomSeedState>;
};

const DEFAULT_MESSAGE = "Seed message #{index:04d} ready for E2EE";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Ensure fetch + Olm are available for matrix-js-sdk when running under Node.
if (typeof globalThis.fetch !== "function") {
  (globalThis as any).fetch = fetch;
}

function formatMessage(template: string, index: number): string {
  const padded = index.toString().padStart(4, "0");
  return template
    .replace(/\{index:04d\}/g, padded)
    .replace(/\{index_padded\}/g, padded)
    .replace(/\{index\}/g, index.toString());
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

// Bounded concurrency pool for mapping async tasks
async function mapPool<T, R>(items: T[], limit: number, worker: (item: T, index: number) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let cursor = 0;
  const runners = new Array(Math.max(1, limit)).fill(0).map(async () => {
    while (true) {
      const i = cursor++;
      if (i >= items.length) break;
      results[i] = await worker(items[i], i);
    }
  });
  await Promise.all(runners);
  return results;
}

function getMembership(client: MatrixClient, roomId: string, userId: string): string | null {
  const room = client.getRoom(roomId);
  if (!room) return null;
  const member = room.getMember?.(userId);
  if (member?.membership) return member.membership as string;
  if (typeof (room as any).getMyMembership === "function" && userId === client.getUserId()) {
    try {
      const membership = (room as any).getMyMembership();
      return typeof membership === "string" ? membership : null;
    } catch {
      return null;
    }
  }
  return null;
}

async function waitForJoinConfirmation(
  client: MatrixClient,
  roomId: string,
  userId: string,
  timeoutMs = 6000,
  pollMs = 200,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const membership = getMembership(client, roomId, userId);
    if (membership === "join") {
      return;
    }
    await sleep(pollMs);
  }
  throw new Error(`Timed out waiting for ${userId} to join ${roomId}`);
}

async function waitForRoomEncryption(
  client: MatrixClient,
  roomId: string,
  timeoutMs = 8000,
  pollMs = 200,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const encrypted = (client as any).isRoomEncrypted?.(roomId) ?? false;
      if (encrypted) return;
    } catch {
      // ignore and continue polling
    }
    await sleep(pollMs);
  }
}

async function waitForBackupUpload(client: MatrixClient, timeoutMs = 20000): Promise<void> {
  const crypto = (client as any).getCrypto?.() ?? (client as any).crypto;
  if (!crypto?.on) return; // nothing to wait for
  let remaining: number | undefined;
  let resolved = false;
  await new Promise<void>((resolve) => {
    const timer = setTimeout(() => {
      if (!resolved) resolve();
    }, timeoutMs);
    const onRemain = (n: number) => {
      remaining = n;
      if (!resolved && typeof n === "number" && n <= 0) {
        resolved = true;
        cleanup();
        resolve();
      }
    };
    const onStatus = () => {
      if (!resolved && typeof remaining === "number" && remaining <= 0) {
        resolved = true;
        cleanup();
        resolve();
      }
    };
    const cleanup = () => {
      clearTimeout(timer);
      try { crypto.off?.("crypto.keyBackupSessionsRemaining", onRemain); } catch {}
      try { crypto.off?.("crypto.keyBackupStatus", onStatus); } catch {}
    };
    try { crypto.on("crypto.keyBackupSessionsRemaining", onRemain); } catch {}
    try { crypto.on("crypto.keyBackupStatus", onStatus); } catch {}
  });
}

async function withRateLimitRetry<T>(
  op: () => Promise<T>,
  label: string,
  opts: RetryOptions = {},
): Promise<T> {
  const retries = opts.retries ?? 6;           // ~6 tries
  const base = opts.baseDelayMs ?? 800;        // base backoff
  const onRateLimit = opts.onRateLimit;
  let attempt = 0;
  while (true) {
    try {
      return await op();
    } catch (e: any) {
      const status = e?.httpStatus ?? e?.status ?? e?.code;
      const errcode = e?.errcode || e?.data?.errcode;
      const headers = e?.httpHeaders;
      const retryAfterHeader = headers?.get?.("retry-after") || headers?.["retry-after"];
      const retryAfterMs = e?.data?.retry_after_ms ?? (retryAfterHeader ? Number(retryAfterHeader) * 1000 : undefined);
      const isRate = status === 429 || errcode === "M_LIMIT_EXCEEDED";
      if (!isRate || attempt >= retries) {
        throw e;
      }
      const jitter = Math.floor(Math.random() * 200);
      const backoff = Math.min(10_000, retryAfterMs ?? base * Math.pow(1.6, attempt)) + jitter;
      onRateLimit?.({
        label,
        attempt: attempt + 1,
        retries,
        delayMs: backoff,
        retryAfterMs,
        error: e,
      });
      console.warn(`[rate-limit] ${label}: attempt ${attempt + 1}/${retries} hit 429; sleeping ${backoff}ms`);
      await sleep(backoff);
      attempt += 1;
    }
  }
}

async function adminFetch(
  baseUrl: string,
  path: string,
  token: string,
  init: RequestInit & { json?: unknown } = {},
): Promise<Response> {
  const url = `${baseUrl}${path}`;
  const headers: Record<string, string> = { ...(init.headers as any) };
  headers["Authorization"] = `Bearer ${token}`;
  if (init.json !== undefined) {
    headers["Content-Type"] = "application/json";
  }
  const res = await fetch(url, { ...init, headers, body: init.json !== undefined ? JSON.stringify(init.json) : (init as any).body });
  return res as any;
}

function stateFile(stateDir: string): string {
  return path.join(stateDir, "seed_state.json");
}

function loadSeedState(statePath: string): SeedStatePayload {
  if (!fs.existsSync(statePath)) {
    return { rooms: {} };
  }
  try {
    const raw = fs.readFileSync(statePath, "utf-8");
    const data = JSON.parse(raw) as JSONObject;
    if (data && typeof data === "object" && data.rooms && typeof data.rooms === "object") {
      return { rooms: { ...(data.rooms as Record<string, RoomSeedState>) } };
    }
  } catch (error) {
    console.warn(`[warn] Failed to parse state file ${statePath}:`, error);
  }
  return { rooms: {} };
}

function persistSeedState(statePath: string, payload: SeedStatePayload): void {
  fs.mkdirSync(path.dirname(statePath), { recursive: true });
  fs.writeFileSync(statePath, JSON.stringify(payload, null, 2));
}

async function registerWithSharedSecret(
  baseUrl: string,
  sharedSecret: string,
  username: string,
  password: string,
  admin: boolean,
): Promise<void> {
  const nonceResp = await fetch(`${baseUrl}/_synapse/admin/v1/register`, { method: "GET" });
  if (!nonceResp.ok) {
    throw new Error(`Failed to fetch registration nonce: ${nonceResp.status}`);
  }
  const nonceBody = (await nonceResp.json()) as JSONObject;
  const nonce = String(nonceBody.nonce ?? "");
  if (!nonce) {
    throw new Error("Registration nonce missing from Synapse response");
  }

  const hmac = createHmac("sha1", Buffer.from(sharedSecret, "utf-8"));
  const adminFlag = admin ? "admin" : "notadmin";
  hmac.update(Buffer.from(nonce, "utf-8"));
  hmac.update(Buffer.from([0]));
  hmac.update(Buffer.from(username, "utf-8"));
  hmac.update(Buffer.from([0]));
  hmac.update(Buffer.from(password, "utf-8"));
  hmac.update(Buffer.from([0]));
  hmac.update(Buffer.from(adminFlag, "utf-8"));

  const payload = {
    nonce,
    username,
    password,
    admin,
    mac: hmac.digest("hex"),
  };

  const response = await fetch(`${baseUrl}/_synapse/admin/v1/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (response.status === 200) {
    console.log(`User '${username}' registered.`);
    return;
  }

  const data = (await response.json().catch(() => ({}))) as JSONObject;
  if (response.status === 400 && data.errcode === "M_USER_IN_USE") {
    console.log(`User '${username}' already exists, continuing.`);
    return;
  }

  throw new Error(`Failed to register user '${username}': ${response.status} ${JSON.stringify(data)}`);
}

async function loginWithPassword(
  baseUrl: string,
  username: string,
  password: string,
  deviceId: string,
  deviceName: string,
): Promise<{ userId: string; deviceId: string; accessToken: string }> {
  const temp = createClient({ baseUrl });
  const res = await withRateLimitRetry(
    () => temp.login("m.login.password", {
      user: username,
      password,
      device_id: deviceId,
      initial_device_display_name: deviceName,
    } as any),
    `login ${username}`,
    { baseDelayMs: 1200 },
  );
  if (!res?.user_id || !res?.access_token) {
    throw new Error("Login response missing user_id or access_token");
  }
  return {
    userId: res.user_id,
    deviceId: res.device_id ?? deviceId,
    accessToken: res.access_token,
  };
}

async function adminLoginToken(baseUrl: string, username: string, password: string, deviceId = "ADMIN_SEED"): Promise<string> {
  const client = createClient({ baseUrl });
  const res = await withRateLimitRetry(
    () => client.login("m.login.password", {
      user: username,
      password,
      device_id: deviceId,
      initial_device_display_name: "Messie Admin Seeder",
    } as any),
    `admin login ${username}`,
    { baseDelayMs: 1200 },
  );
  if (!res?.access_token) throw new Error("Admin login failed");
  return res.access_token;
}

async function waitForClientReady(client: MatrixClient): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const onSync = (state: string, _prev: string, data?: Record<string, unknown>) => {
      if (state === "SYNCING" || state === "PREPARED") {
        (client as any).removeListener("sync", onSync as any);
        resolve();
      } else if (state === "ERROR") {
        (client as any).removeListener("sync", onSync as any);
        reject((data as any)?.error ?? new Error("Sync failed"));
      }
    };
    (client as any).on("sync", onSync as any);
  });
}

async function createMatrixClient(
  config: SeederConfig,
  auth: { userId: string; deviceId: string; accessToken: string },
  secretStorageContext: SecretStorageContext,
): Promise<MatrixClient> {
  const client = createClient({
    baseUrl: config.serverUrl,
    accessToken: auth.accessToken,
    userId: auth.userId,
    deviceId: auth.deviceId,
    timelineSupport: true,
    cryptoCallbacks: {
      getSecretStorageKey: async ({ keys }: { keys: Record<string, any> }, _name: string) => {
        if (!secretStorageContext.privateKey) {
          throw new Error("Secret storage key requested before it was generated");
        }
        let keyId = secretStorageContext.keyId;
        if (!keyId || !keys[keyId]) {
          keyId = Object.keys(keys)[0];
        }
        if (!keyId) {
          throw new Error("No secret storage keys available");
        }
        secretStorageContext.keyId = keyId;
        return [keyId, secretStorageContext.privateKey];
      },
    },
  });

  // Some SDK versions ignore the constructor-supplied cryptoCallbacks until set explicitly.
  // Ensure the callback is registered before initRustCrypto so SSSS can pull the key.
  (client as any).setCryptoCallbacks?.({
    getSecretStorageKey: async ({ keys }: { keys: Record<string, any> }, _name: string) => {
      if (!secretStorageContext.privateKey) {
        throw new Error("Secret storage key requested before it was generated");
      }
      let keyId = secretStorageContext.keyId;
      if (!keyId || !keys[keyId]) {
        keyId = Object.keys(keys)[0];
      }
      if (!keyId) {
        throw new Error("No secret storage keys available");
      }
      secretStorageContext.keyId = keyId;
      return [keyId, secretStorageContext.privateKey];
    },
  });

  // Initialize the modern Rust crypto backend (no olm dependency)
  await (client as any).initRustCrypto({ useIndexedDB: false } as any);
  const ready = waitForClientReady(client);
  (client as any).startClient({ initialSyncLimit: 5 });
  await ready;
  return client;
}

async function ensureEncryptedRoom(
  client: MatrixClient,
  aliasLocalpart: string,
  serverName: string,
): Promise<string> {
  const fullAlias = `#${aliasLocalpart}:${serverName}`;
  try {
    const aliasResult = await withRateLimitRetry(
      () => client.getRoomIdForAlias(fullAlias),
      `lookup alias ${fullAlias}`,
    );
    if (aliasResult?.room_id) {
      return aliasResult.room_id;
    }
  } catch (error) {
    const err = error as { errcode?: string };
    if (err?.errcode && err.errcode !== "M_NOT_FOUND") {
      throw error;
    }
  }

  const creation = await withRateLimitRetry(
    () => client.createRoom({
      visibility: "private",
      preset: "private_chat",
      room_alias_name: aliasLocalpart,
      initial_state: [
        {
          type: "m.room.encryption",
          state_key: "",
          content: { algorithm: "m.megolm.v1.aes-sha2" },
        },
      ],
    } as any),
    `createRoom ${fullAlias}`,
  );

  if (!creation?.room_id) {
    throw new Error(`Room creation for ${fullAlias} did not return room_id`);
  }
  return creation.room_id;
}

async function ensureJoined(
  client: MatrixClient,
  roomId: string,
  opts: { viaServers?: string[]; alias?: string } = {},
): Promise<void> {
  const viaServers = opts.viaServers ?? [];
  const alias = opts.alias;
  try {
    await withRateLimitRetry(
      () => client.joinRoom(roomId, viaServers.length ? { viaServers } : undefined),
      `join ${roomId}`,
    );
    return;
  } catch (error) {
    const err = error as { errcode?: string; data?: { error?: string } };
    const message = err?.data?.error ?? "";
    if (
      err?.errcode === "M_ALREADY_JOINED" ||
      message.includes("already in the room") ||
      message.includes("no servers that are in the room")
    ) {
      return;
    }
    if (alias) {
      try {
        await withRateLimitRetry(
          () => client.joinRoom(alias, viaServers.length ? { viaServers } : undefined),
          `join ${alias}`,
        );
        return;
      } catch (aliasError) {
        const aliasErr = aliasError as { errcode?: string; data?: { error?: string } };
        const aliasMessage = aliasErr?.data?.error ?? "";
        if (
          aliasErr?.errcode === "M_ALREADY_JOINED" ||
          aliasMessage.includes("already in the room") ||
          aliasMessage.includes("no servers that are in the room")
        ) {
          return;
        }
        throw aliasError;
      }
    }
    throw error;
  }
}

type AdminRateOptions = { onRateLimit?: RateLimitListener };

async function adminEnsureEncryptedRoom(
  baseUrl: string,
  adminToken: string,
  aliasLocalpart: string,
  serverName: string,
  rateOpts: AdminRateOptions = {},
): Promise<string> {
  const fullAlias = `#${aliasLocalpart}:${serverName}`;
  // Try resolve alias first
  const got = await withRateLimitRetry(async () => {
    const r = await adminFetch(baseUrl, `/_matrix/client/v3/directory/room/${encodeURIComponent(fullAlias)}`, adminToken, { method: "GET" });
    if (r.status === 200) return (await r.json() as any).room_id as string;
    if (r.status === 429) {
      let j: any = {};
      try { j = await r.json(); } catch {}
      const err: any = new Error("rate-limited alias lookup");
      err.httpStatus = 429;
      err.data = j;
      throw err;
    }
    if (r.status !== 404) throw new Error(`alias lookup ${fullAlias} failed ${r.status}`);
    return null as any;
  }, `admin alias ${fullAlias}`, { onRateLimit: rateOpts.onRateLimit });
  if (got) return got;

  // Create with encryption state
  const created = await withRateLimitRetry(async () => {
    const payload = {
      visibility: "private",
      preset: "private_chat",
      room_alias_name: aliasLocalpart,
      name: `Seed Room ${aliasLocalpart.split("-").pop()}`,
      initial_state: [
        { type: "m.room.encryption", state_key: "", content: { algorithm: "m.megolm.v1.aes-sha2" } },
      ],
    } as const;

    const fallbackClient = async (): Promise<string> => {
      const res = await adminFetch(baseUrl, `/_matrix/client/v3/createRoom`, adminToken, {
        method: "POST",
        json: payload,
      });
      if (res.status === 200) {
        const j = (await res.json()) as any;
        if (!j?.room_id) {
          throw new Error(`createRoom ${fullAlias} -> missing room_id in client response`);
        }
        return j.room_id as string;
      }
      if (res.status === 429) {
        let j: any = {};
        try { j = await res.json(); } catch {}
        const err: any = new Error("rate-limited client createRoom");
        err.httpStatus = 429;
        err.data = j;
        throw err;
      }
      const txt = await res.text();
      throw new Error(`createRoom ${fullAlias} -> client ${res.status} ${txt}`);
    };

    const tryAdmin = await adminFetch(baseUrl, `/_synapse/admin/v1/createRoom`, adminToken, {
      method: "POST",
      json: payload,
    });

    if (tryAdmin.status === 200 || tryAdmin.status === 202) {
      const body = (await tryAdmin.json().catch(() => ({}))) as any;
      if (!body?.room_id) {
        return fallbackClient();
      }
      return body.room_id as string;
    }

    if (tryAdmin.status === 404) {
      return fallbackClient();
    }

    if (tryAdmin.status === 429) {
      let data: any = {};
      try { data = await tryAdmin.json(); } catch {}
      const err: any = new Error("rate-limited admin createRoom");
      err.httpStatus = 429;
      err.data = data;
      throw err;
    }

    let parsed: any = null;
    try {
      parsed = await tryAdmin.json();
    } catch {
      parsed = null;
    }

    if (parsed?.errcode === "M_UNRECOGNIZED" || parsed?.errcode === "M_MISSING_TOKEN") {
      return fallbackClient();
    }

    const txt = parsed ? JSON.stringify(parsed) : await tryAdmin.text();
    throw new Error(`createRoom ${fullAlias} -> admin ${tryAdmin.status} ${txt}`);
  }, `admin createRoom ${fullAlias}`, { onRateLimit: rateOpts.onRateLimit });

  return created;
}

async function adminForceJoin(
  baseUrl: string,
  adminToken: string,
  roomId: string,
  userId: string,
  rateOpts: AdminRateOptions = {},
): Promise<void> {
  await withRateLimitRetry(async () => {
    const annotateRateLimit = async (response: Response, context: string): Promise<never> => {
      if (response.status === 429) {
        let data: any = {};
        try {
          data = await response.json();
        } catch {
          data = { raw: await response.text().catch(() => undefined) };
        }
        const err: any = new Error(`${context} -> 429`);
        err.httpStatus = 429;
        err.data = data;
        throw err;
      }
      const txt = await response.text();
      throw new Error(`${context} -> ${response.status} ${txt}`);
    };

    // Try Synapse v2 admin API first (available in Synapse >=1.80)
    const v2Path = `/_synapse/admin/v2/users/${encodeURIComponent(userId)}/rooms/${encodeURIComponent(roomId)}`;
    let res = await adminFetch(baseUrl, v2Path, adminToken, {
      method: "PUT",
      json: { action: "join" },
    });
    let resBody: string | null = null;
    const bodyText = async (): Promise<string> => {
      if (resBody === null) {
        resBody = await res.text();
      }
      return resBody;
    };

    if (res.status === 200) {
      return undefined as any;
    }
    if (res.status === 202) {
      // Join accepted, Synapse completes asynchronously
      return undefined as any;
    }
    if (res.status === 400) {
      const txt = await bodyText();
      if (/already/i.test(txt)) {
        return undefined as any;
      }
    }
    if (res.status === 429) {
      await annotateRateLimit(res, `admin v2 join ${roomId} ${userId}`);
    }

    if (res.status !== 404) {
      const txt = await bodyText();
      throw new Error(`admin v2 join ${roomId} ${userId} -> ${res.status} ${txt}`);
    }

    // Fall back to admin v1 join endpoint
    const v1Path = `/_synapse/admin/v1/join/${encodeURIComponent(roomId)}`;
    res = await adminFetch(baseUrl, v1Path, adminToken, {
      method: "POST",
      json: { user_id: userId },
    });
    resBody = null;

    if (res.status === 200 || res.status === 202) {
      return undefined as any;
    }
    if (res.status === 400) {
      const txt = await res.text();
      if (/already/i.test(txt)) {
        return undefined as any;
      }
      resBody = txt;
    }
    if (res.status === 429) {
      await annotateRateLimit(res, `admin v1 join ${roomId} ${userId}`);
    }

    if (res.status === 404) {
      // Final fallback: use client /invite; treat success (200/403) as terminal
      const invitePath = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/invite`;
      const invite = await adminFetch(baseUrl, invitePath, adminToken, {
        method: "POST",
        json: { user_id: userId },
      });
      if (invite.status === 200 || invite.status === 403) {
        return undefined as any;
      }
      if (invite.status === 429) {
        await annotateRateLimit(invite, `admin invite ${roomId} ${userId}`);
      }
      const txt = await invite.text();
      throw new Error(`admin invite ${roomId} ${userId} -> ${invite.status} ${txt}`);
    }

    const txt = resBody ?? (await res.text());
    throw new Error(`admin v1 join ${roomId} ${userId} -> ${res.status} ${txt}`);
  }, `admin join ${roomId}`, { onRateLimit: rateOpts.onRateLimit });
}

async function sendSeedMessage(
  client: MatrixClient,
  roomId: string,
  body: string,
): Promise<string> {
  const response = await withRateLimitRetry(
    () => (client as any).sendEvent(roomId, "m.room.message", {
      msgtype: "m.text",
      body,
    }),
    `sendEvent ${roomId}`,
  );
  const typed = response as { event_id?: string };
  if (!typed?.event_id) {
    throw new Error(`sendEvent did not return event id for ${roomId}`);
  }
  return typed.event_id;
}

async function seedHomeserver(config: SeederConfig): Promise<void> {
  const statePath = stateFile(config.stateDir);
  const state = loadSeedState(statePath);

  await registerWithSharedSecret(
    config.serverUrl,
    config.sharedSecret,
    config.adminUsername,
    config.adminPassword,
    true,
  );
  await registerWithSharedSecret(
    config.serverUrl,
    config.sharedSecret,
    config.userUsername,
    config.userPassword,
    false,
  );

  const auth = await loginWithPassword(
    config.serverUrl,
    config.userUsername,
    config.userPassword,
    config.deviceId,
    config.deviceName,
  );

  // Persist access token for test peer helper to avoid login rate limits.
  try {
    const tokenPath = path.join(config.stateDir, "access_token.json");
    await fs.promises.mkdir(config.stateDir, { recursive: true });
    await fs.promises.writeFile(
      tokenPath,
      JSON.stringify({ user_id: auth.userId, device_id: auth.deviceId, access_token: auth.accessToken }, null, 2),
      { encoding: "utf-8" },
    );
  } catch (e) {
    console.warn(`[seed] failed to persist access token: ${e}`);
  }

  // Use admin token to precreate many rooms quickly and force-join the test user
  const adminToken = await adminLoginToken(config.serverUrl, config.adminUsername, config.adminPassword, "MESSIE_ADMIN_SEED");
  const userId = `@${config.userUsername}:${config.serverName}`;
  const aliases: string[] = Array.from({ length: config.roomCount }, (_, i) => `messie-seed-${(i + 1).toString().padStart(4, "0")}`);

  const adminRateOpts: AdminRateOptions = { onRateLimit: (info) => {
    console.warn(`[rate-limit] ${info.label}: attempt ${info.attempt}/${info.retries}; delaying ${info.delayMs}ms`);
  }};

  await mapPool(aliases, config.concurrency, async (aliasLocalpart) => {
    if (state.rooms[aliasLocalpart]?.roomId) return;
    const roomId = await adminEnsureEncryptedRoom(config.serverUrl, adminToken, aliasLocalpart, config.serverName, adminRateOpts);
    await adminForceJoin(config.serverUrl, adminToken, roomId, userId, adminRateOpts);
    state.rooms[aliasLocalpart] = { roomId, lastEventId: "" } as any;
    persistSeedState(statePath, state);
  });

  const secretStorageContext: SecretStorageContext = { privateKey: null };
  const client = await createMatrixClient(config, auth, secretStorageContext);

  try {
    await mapPool(Array.from({ length: config.roomCount }, (_, i) => i + 1), Math.max(1, config.concurrency * 2), async (n) => {
      const index = n;
      const aliasLocalpart = `messie-seed-${index.toString().padStart(4, "0")}`;
      const displayText = formatMessage(config.messageBody, index);

      let roomId = state.rooms[aliasLocalpart]?.roomId;
      let ensuredByClient = false;
      if (!roomId) {
        roomId = await ensureEncryptedRoom(client, aliasLocalpart, config.serverName);
        ensuredByClient = true;
      }

      let waitRetries = 0;
      let joinAttempt = 0;
      while (true) {
        try {
          await ensureJoined(client, roomId, { viaServers: [config.serverName], alias: `#${aliasLocalpart}:${config.serverName}` });
          try {
            await waitForJoinConfirmation(client, roomId, auth.userId);
          } catch (waitError) {
            waitRetries += 1;
            if (waitRetries >= 3) throw waitError;
            if (ensuredByClient) { ensuredByClient = false; continue; }
            ensuredByClient = true;
            roomId = await ensureEncryptedRoom(client, aliasLocalpart, config.serverName);
            continue;
          }
          await waitForRoomEncryption(client, roomId);
          break;
        } catch (joinError) {
          joinAttempt += 1;
          const err = joinError as { errcode?: string; data?: { error?: string } };
          const message = err?.data?.error ?? "";
          const aliasMissing = err?.errcode === "M_NOT_FOUND" || message.includes("alias") || message.includes("not found");
          if (!ensuredByClient && joinAttempt <= 1 && aliasMissing) {
            roomId = await ensureEncryptedRoom(client, aliasLocalpart, config.serverName);
            ensuredByClient = true;
            continue;
          }
          throw joinError;
        }
      }

      const eventId = await sendSeedMessage(client, roomId, displayText);
      state.rooms[aliasLocalpart] = { roomId, lastEventId: eventId };
      persistSeedState(statePath, state);
      console.log(`[ok] Seeded ${aliasLocalpart} (${roomId})`);
    });

    const prepareKeyBackupVersion = (client as any).prepareKeyBackupVersion;
    const createKeyBackupVersion = (client as any).createKeyBackupVersion;
    const enableKeyBackup = (client as any).enableKeyBackup;
    const backupAllGroupSessions = (client as any).backupAllGroupSessions;

    if (
      typeof prepareKeyBackupVersion === "function" &&
      typeof createKeyBackupVersion === "function" &&
      typeof enableKeyBackup === "function" &&
      typeof backupAllGroupSessions === "function"
    ) {
      const prep = await withRateLimitRetry<{
        keyBackupVersion: unknown;
        recovery_key: string;
      }>(
        () => prepareKeyBackupVersion.call(client),
        "prepareKeyBackupVersion",
      );
      const { keyBackupVersion, recovery_key } = prep as any;
      await withRateLimitRetry(
        () => createKeyBackupVersion.call(client, keyBackupVersion),
        "createKeyBackupVersion",
      );
      await withRateLimitRetry(
        () => enableKeyBackup.call(client, keyBackupVersion),
        "enableKeyBackup",
      );
      await withRateLimitRetry(
        () => backupAllGroupSessions.call(client),
        "backupAllGroupSessions",
        { baseDelayMs: 1200 },
      );

      await waitForBackupUpload(client, 20000);
      const recoveryPath = path.join(config.stateDir, "recovery_key.json");
      fs.mkdirSync(config.stateDir, { recursive: true });
      fs.writeFileSync(
        recoveryPath,
        JSON.stringify({ user_id: auth.userId, recovery_key }, null, 2),
      );
      console.log(`Recovery key saved to ${recoveryPath}`);
    } else {
      const cryptoApi = (client as any).getCrypto?.() ?? (client as any).crypto;
      if (
        cryptoApi?.bootstrapSecretStorage &&
        cryptoApi?.createRecoveryKeyFromPassphrase
      ) {
        let generatedKey: any = null;
        await withRateLimitRetry(
          () => cryptoApi.bootstrapSecretStorage({
            setupNewSecretStorage: true,
            setupNewKeyBackup: true,
            createSecretStorageKey: async () => {
              const key = await cryptoApi.createRecoveryKeyFromPassphrase();
              generatedKey = key;
              if (key?.privateKey instanceof Uint8Array) {
                secretStorageContext.privateKey = key.privateKey;
              }
              return key;
            },
          }),
          "bootstrapSecretStorage",
          { baseDelayMs: 1200 },
        );

        if (typeof cryptoApi.checkKeyBackupAndEnable === "function") {
          await withRateLimitRetry(
            () => cryptoApi.checkKeyBackupAndEnable(),
            "checkKeyBackupAndEnable",
            { baseDelayMs: 1200 },
          );
        }

        if (typeof cryptoApi.bootstrapCrossSigning === "function") {
          // Ensure cross-signing keys are generated and stored in 4S so other clients stop nagging
          await withRateLimitRetry(
            () => cryptoApi.bootstrapCrossSigning({} as any),
            "bootstrapCrossSigning",
            { baseDelayMs: 1200 },
          );
        }

        await waitForBackupUpload(client, 20000);
        if (generatedKey?.encodedPrivateKey) {
          const recoveryPath = path.join(config.stateDir, "recovery_key.json");
          fs.mkdirSync(config.stateDir, { recursive: true });
          fs.writeFileSync(
            recoveryPath,
            JSON.stringify({ user_id: auth.userId, recovery_key: generatedKey.encodedPrivateKey }, null, 2),
          );
          console.log(`Recovery key saved to ${recoveryPath}`);
        } else {
          console.warn(
            "[warn] bootstrapSecretStorage completed without yielding a recovery key; skipping file output",
          );
        }
      } else {
        console.warn(
          "[warn] Key backup APIs unavailable on matrix-js-sdk; skipping recovery key generation",
        );
      }
    }
  } finally {
    (client as any).stopClient();
  }

  console.log(`Seeded ${Object.keys(state.rooms).length} rooms.`);
}

async function main(): Promise<void> {
  const argv = await yargs(hideBin(process.argv))
    .option("server-url", {
      type: "string",
      default:
        process.env.MATRIX_SEED_SERVER_URL ??
        process.env.MATRIX_SERVER_URL ??
        "http://localhost:8008",
      describe: "Base URL of the homeserver",
    })
    .option("server-name", {
      type: "string",
      default: process.env.MATRIX_SERVER_NAME ?? "messie.localhost",
      describe: "Server name for room aliases",
    })
    .option("shared-secret", {
      type: "string",
      default: process.env.MATRIX_REGISTRATION_SHARED_SECRET ?? "dev_matrix_shared_secret",
      describe: "Shared secret for Synapse shared-secret registration",
    })
    .option("admin-username", {
      type: "string",
      default: process.env.MATRIX_SEED_ADMIN_USER ?? "bridge-admin",
    })
    .option("admin-password", {
      type: "string",
      default: process.env.MATRIX_SEED_ADMIN_PASSWORD ?? "bridgeAdminPass!",
    })
    .option("user-username", {
      type: "string",
      default: process.env.MATRIX_SEED_USER ?? "bridge-tester",
    })
    .option("user-password", {
      type: "string",
      default: process.env.MATRIX_SEED_PASSWORD ?? "bridgeTesterPass!",
    })
    .option("room-count", {
      type: "number",
      default: Number.parseInt(process.env.MATRIX_SEED_ROOM_COUNT ?? "4", 10),
      describe: "Number of rooms to provision",
    })
    .option("device-id", {
      type: "string",
      default: process.env.MATRIX_SEED_DEVICE_ID ?? "MESSIE_BRIDGE_SEEDER",
    })
    .option("device-name", {
      type: "string",
      default: process.env.MATRIX_SEED_DEVICE_NAME ?? "Messie Seeder",
    })
    .option("state-dir", {
      type: "string",
      default: process.env.MATRIX_SEED_STATE_DIR ?? path.join(__dirname, "../.state"),
      describe: "Directory to store persistent seeder state",
    })
    .option("message-body", {
      type: "string",
      default: process.env.MATRIX_SEED_MESSAGE ?? DEFAULT_MESSAGE,
      describe: "Message template. Use {index} for the room number.",
    })
    .option("admin-delay-ms", {
      type: "number",
      default: Number.parseInt(process.env.MATRIX_SEED_ADMIN_DELAY_MS ?? "400", 10),
      describe: "Delay in ms between admin room provisioning calls",
    })
    .option("concurrency", {
      type: "number",
      default: Number.parseInt(process.env.MATRIX_SEED_CONCURRENCY ?? "2", 10),
      describe: "Max parallel operations for room provisioning and sending",
    })
    .strict()
    .help()
    .parse();

  const config: SeederConfig = {
    serverUrl: argv["server-url"],
    serverName: argv["server-name"],
    sharedSecret: argv["shared-secret"],
    adminUsername: argv["admin-username"],
    adminPassword: argv["admin-password"],
    userUsername: argv["user-username"],
    userPassword: argv["user-password"],
    roomCount: argv["room-count"],
    deviceId: argv["device-id"],
    deviceName: argv["device-name"],
    stateDir: argv["state-dir"],
    messageBody: argv["message-body"],
    adminDelayMs: argv["admin-delay-ms"],
    concurrency: argv["concurrency"],
  };

  await seedHomeserver(config);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
