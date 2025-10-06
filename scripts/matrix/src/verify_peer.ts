import { createClient, ClientEvent, SyncState, MatrixClient } from 'matrix-js-sdk';
import {
  VerificationRequest,
  VerificationRequestEvent,
  VerificationPhase,
  Verifier,
  VerifierEvent,
  ShowSasCallbacks,
  CryptoEvent,
  decodeRecoveryKey,
  type CryptoApi,
  type CryptoCallbacks,
} from 'matrix-js-sdk/lib/crypto-api/index.js';
import { VerificationMethod } from 'matrix-js-sdk/lib/types.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import yargs from 'yargs';
import type { Argv as YargsArgv } from 'yargs';
import { hideBin } from 'yargs/helpers';
import fetch from 'node-fetch';

type CliArgs = {
  'server-url': string;
  username: string;
  password: string;
  'device-name': string;
  'target-device'?: string;
  'device-id'?: string; // alias for target-device for compatibility
};

// __dirname is not defined in ESM; derive it from import.meta.url
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function randId(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 10).toUpperCase()}`;
}

let currentTxnId: string | null = null;

function getTxnIdFromReq(req: any): string | undefined {
  return (
    req?.transactionId ||
    req?.txnId ||
    req?.getRequestId?.() ||
    req?.channel?.transactionId
  );
}

function logReq(prefix: string, req: VerificationRequest): void {
  const initiatedByMe = Boolean((req as any).initiatedByMe);
  let sasSupport = 'unknown';
  try {
    const supports = (req as any).otherPartySupportsMethod?.(VerificationMethod.Sas);
    if (typeof supports === 'boolean') sasSupport = supports ? 'yes' : 'no';
  } catch {}
  const chosen = (req as any).chosenMethod ?? null;
  console.log(
    `${prefix} phase=${req.phase} otherUser=${req.otherUserId} initiatedByMe=${initiatedByMe} otherSupportsSAS=${sasSupport} chosen=${chosen}`,
  );
}

function attachVerifier(v: Verifier): void {
  v.on(VerifierEvent.ShowSas, async (sas: ShowSasCallbacks) => {
    try {
      console.log('[peer] ShowSas → auto-confirming');
      await sas.confirm();
      console.log('[peer] SAS confirmed');
    } catch (e) {
      console.warn(`[peer] SAS confirm failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  });
  v.on(VerifierEvent.Cancel, (e: unknown) => {
    console.warn('[peer] Verifier cancelled:', e);
  });
  void v.verify().catch((e: unknown) => {
    console.warn(`[peer] verifier.verify failed: ${e instanceof Error ? e.message : String(e)}`);
  });
}

async function handleRequest(req: VerificationRequest): Promise<void> {
  const txn = getTxnIdFromReq(req);
  if (txn && currentTxnId && txn !== currentTxnId) {
    console.log(`[peer] received request for stale txn ${txn} (current=${currentTxnId}) — will ignore cancels from it`);
  }
  if (txn && txn !== currentTxnId) {
    currentTxnId = txn;
    console.log(`[peer] tracking verification txn ${currentTxnId}`);
  }
  logReq('[peer] request received →', req);

  // Accept the request once we see it; rust-crypto will include supported methods in the ready
  // event automatically. We avoid touching unimplemented getters like `methods`.
  try {
    console.log('[peer] accepting request');
    await (req as any).accept?.();
    console.log('[peer] accepted request');
  } catch (e) {
    console.warn(`[peer] request.accept failed: ${e instanceof Error ? e.message : String(e)}`);
  }

  const onChange = async (): Promise<void> => {
    console.log(`[peer] request change → phase=${req.phase}`);

    if (req.phase === VerificationPhase.Cancelled) {
      const code = (req as any).cancellationCode ?? (req as any).cancellation?.code;
      const by = (req as any).cancellingUserId ?? (req as any).cancellation?.cancelledBy;
      const txn = getTxnIdFromReq(req);
      const isStale = txn && currentTxnId && txn !== currentTxnId;
      const note = isStale ? ' (stale — ignoring)' : '';
      console.warn(`[peer] verification CANCELLED code=${code} by=${by} txn=${txn}${note}`);
      if (!isStale) {
        req.off(VerificationRequestEvent.Change, onChange);
      }
      return;
    }

    if (req.phase === VerificationPhase.Started && req.verifier) {
      console.log('[peer] request started → attaching verifier');
      attachVerifier(req.verifier);
      req.off(VerificationRequestEvent.Change, onChange);
      return;
    }

    if (req.phase === VerificationPhase.Ready) {
      const iByMe = Boolean((req as any).initiatedByMe);
      if (iByMe) {
        try {
          console.log('[peer] request ready (initiatedByMe) → starting SAS');
          const v = await (req as any).startVerification(VerificationMethod.Sas);
          attachVerifier(v);
          req.off(VerificationRequestEvent.Change, onChange);
        } catch (e) {
          console.warn(`[peer] startVerification failed (will keep listening): ${e instanceof Error ? e.message : String(e)}`);
        }
      } else {
        console.log('[peer] request ready (initiatedByThem) → waiting for their start');
        // keep listening; we'll attach in Started branch
      }
      return;
    }
  };

  req.on(VerificationRequestEvent.Change, onChange);
  await onChange();
}

async function runPeer(): Promise<void> {
  const parser = yargs(hideBin(process.argv)) as YargsArgv<CliArgs>;
  const argv = await parser
    .option('server-url', { type: 'string', demandOption: true })
    .option('username', { type: 'string', demandOption: true })
    .option('password', { type: 'string', demandOption: true })
    .option('device-name', { type: 'string', default: 'Messie SAS Peer' })
    .option('target-device', { type: 'string' })
    .option('device-id', { type: 'string' })
    .strict()
    .help()
    .parseAsync();


  let client: MatrixClient;

  // Prefer persisted access token to avoid login 429s. Fallback to password login.
  let login: { user_id: string; access_token: string; device_id?: string };
  const tokenCandidates: string[] = [];
  if (process.env.ACCESS_TOKEN_PATH) tokenCandidates.push(process.env.ACCESS_TOKEN_PATH);
  tokenCandidates.push('/state/access_token.json');
  tokenCandidates.push(path.resolve(process.cwd(), 'scripts/matrix/.state/access_token.json'));
  tokenCandidates.push(path.resolve(__dirname, '..', '.state', 'access_token.json'));
  tokenCandidates.push(path.resolve('/state', '..', 'scripts', 'matrix', '.state', 'access_token.json'));

  let session: { user_id: string; access_token: string; device_id?: string } | null = null;
  for (const p of tokenCandidates) {
    try {
      if (fs.existsSync(p)) {
        const raw = fs.readFileSync(p, 'utf-8');
        const parsed = JSON.parse(raw);
        if (parsed?.user_id && parsed?.access_token) {
          session = {
            user_id: String(parsed.user_id),
            access_token: String(parsed.access_token),
            device_id: parsed.device_id ? String(parsed.device_id) : undefined,
          };
          console.log('[peer] using persisted access token from', p);
          break;
        }
      }
    } catch {}
  }

  if (session) {
    login = session;
  } else {
    const tmpClient = createClient({ baseUrl: argv['server-url'] });
    const res = await tmpClient.loginRequest({
      type: 'm.login.password',
      identifier: { type: 'm.id.user', user: argv.username },
      password: argv.password,
      initial_device_display_name: argv['device-name'],
    });
    login = res as any;
    // Persist token for future runs to avoid 429s
    try {
      const outPath = process.env.ACCESS_TOKEN_PATH || '/state/access_token.json';
      fs.mkdirSync(path.dirname(outPath), { recursive: true });
      fs.writeFileSync(
        outPath,
        JSON.stringify({ user_id: login.user_id, device_id: login.device_id, access_token: login.access_token }, null, 2),
        'utf-8',
      );
      console.log('[peer] persisted access token to', outPath);
    } catch (e) {
      console.warn('[peer] failed to persist access token:', e instanceof Error ? e.message : String(e));
    }
  }
  console.log(`[peer] logged in as ${login.user_id} device ${login.device_id ?? '(unknown)'}`);

  // Persist the active device id so host tests can target it (bind-mounted /state)
  try {
    const outPath = process.env.PEER_INFO_PATH || '/state/sas_peer.json';
    const payload = {
      user_id: login.user_id,
      device_id: login.device_id,
      ts: Date.now(),
      ready: false,
    } as const;
    fs.writeFileSync(outPath, JSON.stringify(payload));
    console.log('[peer] wrote peer info to', outPath);
  } catch (e) {
    console.warn('[peer] failed to write peer info file:', e instanceof Error ? e.message : String(e));
  }

  // --- Prepare recovery key and preinstall SSSS callback BEFORE client construction ---
  const candidates: string[] = [];
  const envPath = process.env.RECOVERY_KEY_PATH;
  if (envPath) candidates.push(envPath);
  candidates.push(path.resolve(process.cwd(), 'scripts/matrix/.state/recovery_key.json'));
  candidates.push(path.resolve(__dirname, '..', '.state', 'recovery_key.json'));
  candidates.push('/state/recovery_key.json');
  candidates.push(path.resolve('/state', '..', 'scripts', 'matrix', '.state', 'recovery_key.json'));

  let statePath: string | null = null;
  for (const p of candidates) {
    try { if (fs.existsSync(p)) { statePath = p; break; } } catch { /* ignore */ }
  }

  let encodedRecoveryKey: string | null = null;
  if (statePath) {
    try {
      const recoveryRaw = fs.readFileSync(statePath, 'utf-8');
      const recovery = JSON.parse(recoveryRaw) as { recovery_key?: string };
      if (typeof recovery.recovery_key === 'string' && recovery.recovery_key.trim().length > 0) {
        encodedRecoveryKey = recovery.recovery_key.replace(/\s+/g, '').trim();
        console.log('[peer] found recovery key file at', statePath);
      } else {
        console.warn('[peer] recovery_key.json found but no "recovery_key" field');
      }
    } catch (e) {
      console.warn('[peer] failed reading recovery_key.json:', e instanceof Error ? e.message : String(e));
    }
  } else {
    console.warn('[peer] recovery_key.json not found; set RECOVERY_KEY_PATH or place it under scripts/matrix/.state/. Tried:');
    for (const p of candidates) console.warn('  -', p);
  }

  // Define the callback with the exact signature the SDK expects
  const getSecretStorageKey: CryptoCallbacks['getSecretStorageKey'] = async (
    opts,
    _name,
  ): Promise<[string, Uint8Array] | null> => {
    const ids = Object.keys(opts.keys);
    if (ids.length === 0) {
      throw new Error('No secret storage keys available');
    }
    const keyId = ids[0];
    if (!encodedRecoveryKey) {
      return null;
    }
    const privateKey = decodeRecoveryKey(encodedRecoveryKey);
    return [keyId, privateKey];
  };

  // Build the client with cryptoCallbacks provided up-front so the SDK has it during init
  client = createClient({
    baseUrl: argv['server-url'],
    accessToken: login.access_token,
    userId: login.user_id,
    deviceId: login.device_id,
    cryptoCallbacks: { getSecretStorageKey },
  });

  await client.initRustCrypto({ useIndexedDB: false });

  // Low-level visibility into verification to-device messages (debug aid)
  client.on(ClientEvent.ToDeviceEvent as any, (ev: any) => {
    const t = ev?.getType?.();
    if (!t || !String(t).startsWith('m.key.verification.')) return;
    try {
      const c = ev.getContent?.() ?? {};
      const s = ev.getSender?.() ?? ev.getSender;
      const txn = (c && (c.transaction_id || c.txn_id)) as string | undefined;
      const stale = txn && currentTxnId && txn !== currentTxnId ? ' (stale)' : '';
      console.log('[peer][to-device]', t, 'from=', s, 'txn=', txn, stale, 'content=', JSON.stringify(c));
    } catch (e) {
      console.log('[peer][to-device]', t, '(failed to stringify content)');
    }
  });


  client.on(CryptoEvent.VerificationRequestReceived, async (req: VerificationRequest) => {
    console.log(`[peer] verificationRequestReceived from ${req.otherUserId} (phase=${req.phase})`);
    await handleRequest(req);
  });

  await client.startClient({ initialSyncLimit: 1 });

  await new Promise<void>((resolve) => {
    const onSync = (state: SyncState): void => {
      if (state === SyncState.Prepared || state === SyncState.Syncing) {
        client.removeListener(ClientEvent.Sync, onSync);
        resolve();
      }
    };
    client.on(ClientEvent.Sync, onSync);
  });

  // Restore 4S / cross-signing from recovery key after sync (frontend-aligned timing)
  try {
    const crypto: CryptoApi | undefined = client.getCrypto?.();
    if (!crypto) {
      console.warn('[peer] crypto API unavailable on client');
    } else if (!encodedRecoveryKey) {
      console.warn('[peer] skipping recovery restore: no recovery key available');
    } else {
      // Align with frontend: first touch device verification status to ensure
      // the SDK populates our public identity / device list as needed.
      try {
        const uid = client.getUserId();
        const did = client.getDeviceId();
        if (uid && did && typeof crypto.getDeviceVerificationStatus === 'function') {
          await crypto.getDeviceVerificationStatus(uid, did);
          console.log('[peer] ensured device verification status before cross-signing bootstrap');
        }
      } catch (e) {
        console.warn('[peer] getDeviceVerificationStatus preflight failed (continuing):', e);
      }

      console.log('[peer] restoring secret storage using recovery key...');
      // This will call our cryptoCallbacks.getSecretStorageKey and unlock 4S
      await crypto.bootstrapSecretStorage({
        setupNewSecretStorage: false,
        setupNewKeyBackup: false,
      });
      // Proactively ensure our public identity is available via /keys/query
      try {
        const uid = client.getUserId();
        if (uid && typeof (client as any).downloadKeysForUsers === 'function') {
          await (client as any).downloadKeysForUsers([uid]);
          console.log('[peer] performed /keys/query for own user');
        }
        // Wait until the rust store processes the response and reports public XSign keys
        const waitForPublicIdentity = async (timeoutMs = 3000, pollMs = 150): Promise<boolean> => {
          const start = Date.now();
          while (Date.now() - start < timeoutMs) {
            try {
              const ok = await crypto.userHasCrossSigningKeys();
              if (ok) return true;
            } catch {}
            await new Promise((r) => setTimeout(r, pollMs));
          }
          return false;
        };
        const havePub = await waitForPublicIdentity();
        console.log('[peer] public cross-signing keys present =', havePub);
      } catch (e) {
        console.warn('[peer] /keys/query (downloadKeysForUsers) or wait failed (continuing):', e);
      }

      // Ensure cross-signing keys are fetched and device gets trusted if appropriate
      if (typeof crypto.bootstrapCrossSigning === 'function') {
        const tryBootstrap = async (): Promise<void> => {
          await crypto.bootstrapCrossSigning({});
        };
        try {
          await tryBootstrap();
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          if (msg.includes('importCrossSigningKeys')) {
            console.warn('[peer] bootstrapCrossSigning import failed; ensuring public identity then retrying');
            try {
              const uid = client.getUserId();
              if (uid && typeof (client as any).downloadKeysForUsers === 'function') {
                await (client as any).downloadKeysForUsers([uid]);
                // wait for processing
                const ok = await (async () => {
                  const start = Date.now();
                  while (Date.now() - start < 3000) {
                    if (await crypto.userHasCrossSigningKeys()) return true;
                    await new Promise((r) => setTimeout(r, 150));
                  }
                  return false;
                })();
                console.log('[peer] retried /keys/query; public identity ready =', ok);
              }
            } catch {}
            await tryBootstrap();
          } else {
            throw e;
          }
        }
      }
      if (typeof crypto.checkKeyBackupAndEnable === 'function') {
        await crypto.checkKeyBackupAndEnable();
      }
      console.log('[peer] recovery key restored — device should now be eligible for SAS fan-out');
    }
  } catch (e) {
    console.warn('[peer] failed to restore recovery key:', e);
  }

  // Before signalling readiness, ensure our one-time keys are uploaded so peers can claim them.
  try {
    const baseUrl = (client as any).baseUrl || argv['server-url'];
    const token = login.access_token;
    const getCounts = async (): Promise<number> => {
      const url = new URL('/_matrix/client/v3/keys/upload', baseUrl);
      const res = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: '{}',
      });
      if (!res.ok) {
        // Treat 429 with backoff as transient
        const txt = await res.text().catch(() => '');
        throw new Error(`keys/upload -> ${res.status} ${txt}`);
      }
      const data = (await res.json().catch(() => ({} as any))) as any;
      const counts = ((data as any)?.one_time_key_counts ?? {}) as Record<string, number>;
      let total = 0;
      for (const k of Object.keys(counts)) {
        const v = Number(counts[k] ?? 0);
        if (!Number.isNaN(v)) total += v;
      }
      return total;
    };

    const waitForOtk = async (timeoutMs = 7000, pollMs = 200): Promise<boolean> => {
      const start = Date.now();
      while (Date.now() - start < timeoutMs) {
        try {
          const total = await getCounts();
          if (total > 0) {
            console.log('[peer] one-time key counts available =', total);
            return true;
          }
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          if (!/429/.test(msg)) console.warn('[peer] keys/upload probe failed (continuing):', msg);
        }
        await new Promise((r) => setTimeout(r, pollMs));
      }
      return false;
    };

    const haveOtk = await waitForOtk();
    if (!haveOtk) {
      console.warn('[peer] one-time keys not observed after timeout; proceeding anyway');
    }
  } catch (e) {
    console.warn('[peer] failed while probing one-time key counts (continuing):', e instanceof Error ? e.message : String(e));
  }

  // Signal readiness to the host: we have started syncing and attempted SSSS/cross-signing restore.
  try {
    const outPath = process.env.PEER_INFO_PATH || '/state/sas_peer.json';
    const payload = {
      user_id: client.getUserId?.(),
      device_id: client.getDeviceId?.(),
      ts: Date.now(),
      ready: true,
    };
    fs.writeFileSync(outPath, JSON.stringify(payload));
    console.log('[peer] updated peer info with ready=true at', outPath);
  } catch (e) {
    console.warn('[peer] failed to update peer info file (ready):', e instanceof Error ? e.message : String(e));
  }

  const userId = client.getUserId();

  const targetDevice = argv['target-device'] || argv['device-id'];
  if (targetDevice && userId && client.getCrypto()) {
    console.log(`[peer] proactively requesting verification from ${userId} device ${targetDevice}`);
    try {
      // tiny delay to ensure OTK upload went through
      await new Promise((r) => setTimeout(r, 250));
      const req = await client.getCrypto()!.requestDeviceVerification(userId, targetDevice);
      await handleRequest(req);
    } catch (e) {
      console.warn(`[peer] failed to initiate verification: ${String(e)}`);
    }
  }

  process.on('unhandledRejection', (reason) => {
    console.error('[peer] UnhandledRejection:', reason);
  });
  process.on('uncaughtException', (err) => {
    console.error('[peer] UncaughtException:', err);
  });
  process.on('SIGTERM', () => {
    console.error('[peer] SIGTERM received');
  });
  process.on('SIGINT', () => {
    console.error('[peer] SIGINT received');
  });
  process.on('beforeExit', (code) => {
    console.error('[peer] beforeExit code=', code);
  });
  process.on('exit', (code) => {
    console.error('[peer] exit code=', code);
  });

  process.stdin.resume();
  // Ensure the process does not exit due to lack of handles in detached Docker mode.
  await new Promise<void>(() => { /* keep alive */ });
}

runPeer().catch((err) => {
  console.error(err);
  process.exit(1);
});
