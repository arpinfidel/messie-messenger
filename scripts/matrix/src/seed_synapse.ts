#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { createHmac } from "crypto";
import fetch from "node-fetch";
import sdk, { type MatrixClient, createClient } from "matrix-js-sdk";
import { ClientEvent, EventType, MsgType, Visibility, Preset } from "matrix-js-sdk";
import type { RoomMessageEventContent } from "matrix-js-sdk/lib/@types/events";
import type { CryptoApi } from "matrix-js-sdk/lib/crypto-api";
import type { MatrixEvent } from "matrix-js-sdk/lib/models/event";
import type { Room } from "matrix-js-sdk/lib/models/room";
import loglevel from "loglevel";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

// Minimal local compat type for SSSS key descriptions (SDK does not export the full type)
type SecretStorageKeyDescriptionCompat = { algorithm: string };

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
  userUsername: string; // used when userCount = 1 or as default prefix
  userPassword: string;
  userCount: number; // number of seeding users
  userPrefix: string; // prefix for usernames when userCount > 1
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
  creator?: string; // userId of the account that created the room
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

// Keep matrix-js-sdk logs at warn to reduce noise during seeding
try { loglevel.setLevel("warn"); } catch (e) { console.warn("[seed] failed to set loglevel:", e instanceof Error ? e.message : String(e)); }
try { (sdk as any).logger?.setLevel?.("warn"); } catch (e) { console.warn("[seed] failed to set matrix-js-sdk logger level:", e instanceof Error ? e.message : String(e)); }

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
  if (userId === client.getUserId()) {
    try {
      const membership = room.getMyMembership();
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
    const encrypted = client.isRoomEncrypted(roomId);
    if (encrypted) return;
    await sleep(pollMs);
  }
}

async function waitForBackupUpload(_client: MatrixClient, timeoutMs = 20000): Promise<void> {
  // We can't reliably detect enablement across SDK versions with types alone; wait a short grace period.
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(250);
  }
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
      // Respect retry_after_ms exactly when present; fallback to fixed 5000ms
      const backoff = typeof retryAfterMs === "number" ? retryAfterMs : 5000;
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
  const url = new URL("/_matrix/client/v3/login", baseUrl);
  const body = {
    type: "m.login.password",
    identifier: { type: "m.id.user", user: username },
    password,
    device_id: deviceId,
    initial_device_display_name: deviceName,
  } as const;

  const doLogin = async (): Promise<any> => {
    const r = await fetch(url.toString(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (r.ok) return r.json();
    if (r.status === 429) {
      let data: any = {};
      try { data = await r.json(); } catch (e) { console.warn("[seed][login] failed to parse 429 JSON:", e instanceof Error ? e.message : String(e)); }
      const err: any = new Error("rate-limited login");
      err.httpStatus = 429;
      err.data = data;
      err.httpHeaders = r.headers;
      throw err;
    }
    // Bubble other errors with basic info
    const txt = await r.text().catch(() => "");
    const e: any = new Error(`login ${username} -> ${r.status} ${txt}`);
    e.httpStatus = r.status;
    e.httpHeaders = r.headers;
    try { e.data = JSON.parse(txt); } catch (e2) { console.warn("[seed][login] failed to parse error JSON:", e2 instanceof Error ? e2.message : String(e2)); }
    throw e;
  };

  const res = await withRateLimitRetry(doLogin, `login ${username}`, { baseDelayMs: 800 });
  if (!res?.user_id || !res?.access_token) {
    throw new Error("Login response missing user_id or access_token");
  }
  return {
    userId: res.user_id,
    deviceId: res.device_id ?? deviceId,
    accessToken: res.access_token,
  };
}

async function waitForClientReady(client: MatrixClient): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const onSync = (state: string, _prev: string, data?: unknown) => {
      if (state === "SYNCING" || state === "PREPARED") {
        client.removeListener(ClientEvent.Sync, onSync as unknown as (...args: unknown[]) => void);
        resolve();
      } else if (state === "ERROR") {
        client.removeListener(ClientEvent.Sync, onSync as unknown as (...args: unknown[]) => void);
        reject(new Error(typeof data === "object" && data !== null && "error" in (data as Record<string, unknown>) ? String((data as Record<string, unknown>)["error"]) : "Sync failed"));
      }
    };
    client.on(ClientEvent.Sync, onSync as unknown as (...args: unknown[]) => void);
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
      getSecretStorageKey: async ({ keys }: { keys: Record<string, SecretStorageKeyDescriptionCompat> }, _name?: string) => {
        if (!secretStorageContext.privateKey) throw new Error("Secret storage key requested before it was generated");
        let keyId = secretStorageContext.keyId;
        if (!keyId || !(keyId in keys)) {
          const ids = Object.keys(keys);
          keyId = ids.length > 0 ? ids[0] : undefined;
        }
        if (!keyId) throw new Error("No secret storage keys available");
        secretStorageContext.keyId = keyId;
        return [keyId, secretStorageContext.privateKey] as const;
      },
    },
  });

  await client.initRustCrypto({ useIndexedDB: false });
  const ready = waitForClientReady(client);
  client.startClient({ initialSyncLimit: 5 });
  await ready;
  return client;
}

// Create a minimal client suitable for sending in E2EE rooms without 4S/cross-signing.
// Does not register secret storage callbacks to avoid UIA flows for device signing uploads.
async function createSenderClient(
  config: SeederConfig,
  auth: { userId: string; deviceId: string; accessToken: string },
): Promise<MatrixClient> {
  const client = createClient({
    baseUrl: config.serverUrl,
    accessToken: auth.accessToken,
    userId: auth.userId,
    deviceId: auth.deviceId,
    timelineSupport: true,
  });
  await client.initRustCrypto({ useIndexedDB: false });
  const ready = waitForClientReady(client);
  client.startClient({ initialSyncLimit: 5 });
  await ready;
  return client;
}

async function ensureEncryptedRoom(
  client: MatrixClient,
  aliasLocalpart: string,
  serverName: string,
  invites?: string[],
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
      visibility: Visibility.Private,
      preset: Preset.PrivateChat,
      room_alias_name: aliasLocalpart,
      invite: invites && invites.length ? invites : undefined,
      initial_state: [
        {
          type: "m.room.encryption",
          state_key: "",
          content: { algorithm: "m.megolm.v1.aes-sha2" },
        },
      ],
    }),
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

async function sendSeedMessage(
  client: MatrixClient,
  roomId: string,
  body: string,
): Promise<string> {
  const response = await withRateLimitRetry(
    () => {
      const content: RoomMessageEventContent = { msgtype: MsgType.Text, body };
      return client.sendEvent(roomId, EventType.RoomMessage, content);
    },
    `sendEvent ${roomId}`,
  );
  const eventId = (response as { event_id?: string }).event_id;
  if (!eventId) {
    throw new Error(`sendEvent did not return event id for ${roomId}`);
  }
  return eventId;
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
  // Build user list (single user when userCount <= 1, otherwise prefix + index)
  const users: Array<{ username: string; password: string; userId: string; deviceId: string; deviceName: string }> = [];
  const count = Math.max(1, config.userCount || 1);
  // Always multi-user: first user is unsuffixed (e.g., 'bridge-tester'), others are '<prefix>-02..NN'
  const prefix = (config.userPrefix || config.userUsername || "bridge-tester").replace(/\s+/g, "-");
  const pad = String(Math.max(2, count)).length; // at least 2-digit padding when multiple
  // First (primary) user unsuffixed
  users.push({
    username: config.userUsername,
    password: config.userPassword,
    userId: `@${config.userUsername}:${config.serverName}`,
    deviceId: `${config.deviceId}_${config.userUsername}`,
    deviceName: `${config.deviceName} [${config.userUsername}]`,
  });
  // Additional users start at 02 to avoid clashing with unsuffixed primary
  for (let i = 2; i <= count; i += 1) {
    const uname = `${prefix}-${String(i).padStart(pad, "0")}`;
    users.push({
      username: uname,
      password: config.userPassword,
      userId: `@${uname}:${config.serverName}`,
      deviceId: `${config.deviceId}_${uname}`,
      deviceName: `${config.deviceName} [${uname}]`,
    });
  }

  // Register all users
  await Promise.all(users.map((u) =>
    registerWithSharedSecret(
      config.serverUrl,
      config.sharedSecret,
      u.username,
      u.password,
      false,
    )
  ));

  type UserAuth = { userId: string; deviceId: string; accessToken: string };
  // Tracking structures
  const secretStorageContexts: SecretStorageContext[] = users.map(() => ({ privateKey: null }));
  const startedClients: MatrixClient[] = [];
  const auths: Array<UserAuth | null> = new Array(users.length).fill(null);
  const authResolvers: Array<((a: UserAuth) => void) | null> = new Array(users.length).fill(null);
  const authPromises: Array<Promise<UserAuth>> = users.map((_u, idx) => new Promise<UserAuth>((resolve) => { authResolvers[idx] = resolve; }));
  const clientPromises: Array<Promise<MatrixClient> | null> = new Array(users.length).fill(null);
  async function enablePrimaryRecovery(client: MatrixClient, primaryUserId: string): Promise<void> {
    const crypto = client.getCrypto?.();
    if (!crypto) throw new Error("Crypto API unavailable on Matrix client");

    // 1) Create a recovery key and bootstrap 4S (with new key backup).
    const recovery = await withRateLimitRetry(
      () => crypto.createRecoveryKeyFromPassphrase(),
      "createRecoveryKeyFromPassphrase",
    );

    await withRateLimitRetry(
      () =>
        crypto.bootstrapSecretStorage({
          setupNewSecretStorage: true,
          setupNewKeyBackup: true,
          createSecretStorageKey: async () => {
            // Persist private key for SDK callbacks that need it later
            const maybePriv = (recovery as unknown as { privateKey?: Uint8Array }).privateKey;
            if (maybePriv instanceof Uint8Array) {
              secretStorageContexts[0].privateKey = maybePriv;
            }
            return recovery;
          },
        }),
      "bootstrapSecretStorage",
    );

    // 1.5) Bootstrap cross-signing if available (helps Element stop prompting and stores keys in 4S).
    await withRateLimitRetry(
      () => crypto.bootstrapCrossSigning({}),
      "bootstrapCrossSigning",
    );

    // 2) Ensure there is a server-side backup: if none, create one via CryptoApi, then recheck.
    const existing = await withRateLimitRetry(
      () => crypto.checkKeyBackupAndEnable(),
      "checkKeyBackupAndEnable",
    );
    if (!existing) {
      await withRateLimitRetry(
        () => crypto.resetKeyBackup(),
        "resetKeyBackup",
      );
      await withRateLimitRetry(
        () => crypto.checkKeyBackupAndEnable(),
        "checkKeyBackupAndEnable(recheck)",
      );
    }

    // 5) Wait briefly for any pending uploads (if there are sessions).
    await waitForBackupUpload(client, 20000);

    // 6) Persist encoded recovery key for future restore.
    const recoveryPath = path.join(config.stateDir, "recovery_key.json");
    fs.mkdirSync(config.stateDir, { recursive: true });
    const encoded = (recovery as unknown as { encodedPrivateKey?: string }).encodedPrivateKey;
    if (!encoded) throw new Error("Recovery key encoding missing after bootstrap");
    fs.writeFileSync(
      recoveryPath,
      JSON.stringify({ user_id: primaryUserId, recovery_key: encoded }, null, 2),
    );
    console.log(`Recovery key saved to ${recoveryPath}`);
  }
  const available: number[] = [];
  const waiters: Array<() => void> = [];
  const notifyAvailable = (): void => { while (waiters.length) { const w = waiters.shift(); try { w && w(); } catch (e) { console.warn("[seed] waiter callback threw:", e instanceof Error ? e.message : String(e)); } } };
  const waitForAvailable = async (): Promise<void> => {
    if (available.length > 0) return;
    await new Promise<void>((resolve) => { waiters.push(resolve); });
  };

  // Enable primary recovery once, after first seeded room sends an encrypted message
  let primaryRecoveryEnabled = false;

  // Background sequential login loop; resolves per-user authPromises
  (async () => {
    for (let i = 0; i < users.length; i += 1) {
      const u = users[i];
      const a = await loginWithPassword(
        config.serverUrl,
        u.username,
        u.password,
        u.deviceId,
        u.deviceName,
      );
      auths[i] = a;
      authResolvers[i]?.(a);
      available.push(i);
      notifyAvailable();

      if (i === 0) {
        // Persist access token for test peer helper to avoid login rate limits.
        try {
          const tokenPath = path.join(config.stateDir, "access_token.json");
          await fs.promises.mkdir(config.stateDir, { recursive: true });
          await fs.promises.writeFile(
            tokenPath,
            JSON.stringify({ user_id: a.userId, device_id: a.deviceId, access_token: a.accessToken }, null, 2),
            { encoding: "utf-8" },
          );
        } catch (e) {
          console.warn(`[seed] failed to persist access token: ${e}`);
        }

        // Create primary full client
        if (!clientPromises[0]) {
          clientPromises[0] = (async () => {
            const c = await createMatrixClient(config, a, secretStorageContexts[0]);
            startedClients.push(c);
            return c;
          })();
        }
      }
    }
  })();

  const aliases: string[] = Array.from({ length: config.roomCount }, (_, i) => `messie-seed-${(i + 1).toString().padStart(4, "0")}`);
  // Sequential loop that round-robins over whichever users have logged in so far
  for (let i = 0; i < aliases.length; i += 1) {
    const aliasLocalpart = aliases[i];
    if (available.length === 0) {
      await waitForAvailable();
    }
    const poolSize = Math.max(available.length, 1);
    const pick = available[i % poolSize];
    const creatorIdx = typeof pick === 'number' ? pick : 0;
    const creatorAuth = auths[creatorIdx] ?? await authPromises[creatorIdx];
    if (!clientPromises[creatorIdx]) {
      clientPromises[creatorIdx] = (async () => {
        const c = creatorIdx === 0
          ? await createMatrixClient(config, creatorAuth, secretStorageContexts[0])
          : await createSenderClient(config, creatorAuth);
        startedClients.push(c);
        return c;
      })();
    }
    const creatorClient = await clientPromises[creatorIdx]!;
    const creatorUser = users[creatorIdx];

    let roomId = state.rooms[aliasLocalpart]?.roomId;
    if (!roomId) {
      const primaryUserId = users[0].userId;
      const invitees = primaryUserId !== creatorUser.userId ? [primaryUserId] : [];
      roomId = await ensureEncryptedRoom(creatorClient, aliasLocalpart, config.serverName, invitees);
      state.rooms[aliasLocalpart] = { roomId, lastEventId: "", creator: creatorAuth.userId };
      persistSeedState(statePath, state);
    }

    try {
      await ensureJoined(creatorClient, roomId, { viaServers: [config.serverName], alias: `#${aliasLocalpart}:${config.serverName}` });
      await waitForJoinConfirmation(creatorClient, roomId, creatorAuth.userId);
    } catch (e) {
      console.warn("[seed] creator join/confirm failed:", e instanceof Error ? e.message : String(e));
    }

    try {
      if (!clientPromises[0]) {
        const primaryAuth = auths[0] ?? await authPromises[0];
        clientPromises[0] = (async () => {
          const c = await createMatrixClient(config, primaryAuth, secretStorageContexts[0]);
          startedClients.push(c);
          return c;
        })();
      }
      const primaryClient = await clientPromises[0]!;
      await ensureJoined(primaryClient, roomId, { viaServers: [config.serverName], alias: `#${aliasLocalpart}:${config.serverName}` });
      await waitForJoinConfirmation(primaryClient, roomId, users[0].userId);
    } catch (joinErr: any) {
      const msg = joinErr?.data?.error ?? String(joinErr?.message ?? "");
      const forbidden = joinErr?.errcode === "M_FORBIDDEN" || /forbidden/i.test(msg);
      if (forbidden) {
        await withRateLimitRetry(
          () => creatorClient.invite(roomId, users[0].userId),
          `invite ${roomId} ${users[0].userId}`,
        );
        const primaryClient = await clientPromises[0]!;
        await ensureJoined(primaryClient, roomId, { viaServers: [config.serverName], alias: `#${aliasLocalpart}:${config.serverName}` });
        await waitForJoinConfirmation(primaryClient, roomId, users[0].userId);
      } else {
        throw joinErr;
      }
    }

    // If already sent on a previous run, skip sending
    if (state.rooms[aliasLocalpart]?.lastEventId) {
      continue;
    }


    await waitForRoomEncryption(creatorClient, roomId);
    const displayText = formatMessage(config.messageBody, i + 1);
    const eventId = await sendSeedMessage(creatorClient, roomId, displayText);
    state.rooms[aliasLocalpart] = { roomId, lastEventId: eventId, creator: creatorAuth.userId };
    persistSeedState(statePath, state);

    // After the first encrypted message exists, enable backup for the primary device
    if (!primaryRecoveryEnabled) {
      const primaryClient = await clientPromises[0]!;
      try {
        await enablePrimaryRecovery(primaryClient, users[0].userId);
        primaryRecoveryEnabled = true;
      } catch (e) {
        console.warn(`[seed] primary recovery/backup enable failed: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
  }

  try {
    await mapPool(Array.from({ length: config.roomCount }, (_, i) => i + 1), Math.max(1, config.concurrency * 2), async (n) => {
      const index = n;
      const aliasLocalpart = `messie-seed-${index.toString().padStart(4, "0")}`;
      const displayText = formatMessage(config.messageBody, index);

      let roomId = state.rooms[aliasLocalpart]?.roomId;
      let ensuredByClient = false;
      // Skip rooms already sent during creation pass
      if (state.rooms[aliasLocalpart]?.lastEventId) {
        return;
      }
      // Determine sender = room creator (fallback to assigned idx)
      let sendIdx = (() => {
        const creator = state.rooms[aliasLocalpart]?.creator;
        if (creator) {
          const j = users.findIndex((u) => u.userId === creator);
          if (j >= 0) return j;
        }
        return (index - 1) % users.length;
      })();
      if (!clientPromises[sendIdx]) {
        clientPromises[sendIdx] = (async () => {
          const senderAuth = auths[sendIdx] ?? await authPromises[sendIdx];
          const c = sendIdx === 0
            ? await createMatrixClient(config, senderAuth, secretStorageContexts[0])
            : await createSenderClient(config, senderAuth);
          startedClients.push(c);
          return c;
        })();
      }
      const client = await clientPromises[sendIdx]!;
      const auth = auths[sendIdx] ?? await authPromises[sendIdx];

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


      await waitForRoomEncryption(client, roomId);
      const eventId = await sendSeedMessage(client, roomId, displayText);
      state.rooms[aliasLocalpart] = { roomId, lastEventId: eventId };
      persistSeedState(statePath, state);
      console.log(`[ok] Seeded ${aliasLocalpart} (${roomId})`);
    });


  } finally {
    for (const c of startedClients as any[]) {
      try { c.stopClient(); } catch {}
    }
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
    .option("user-count", {
      type: "number",
      default: Number.parseInt(process.env.MATRIX_SEED_USER_COUNT ?? "4", 10),
      describe: "Number of users to seed with (distributes rooms across them)",
    })
    .option("user-prefix", {
      type: "string",
      default: process.env.MATRIX_SEED_USER_PREFIX ?? "",
      describe: "Prefix for usernames when using multiple users (e.g. 'bridge-tester')",
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
    // creation-mode removed: client-only multi-user is the default and only mode
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
    userCount: argv["user-count"],
    userPrefix: argv["user-prefix"],
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
