// frontend/src/lib/matrix/MatrixViewModel.ts
import { type CryptoCallbacks, type Verifier, VerifierEvent, VerificationPhase, VerificationRequestEvent, type VerificationRequest, type ShowSasCallbacks } from 'matrix-js-sdk/lib/crypto-api';
import { decodeRecoveryKey } from 'matrix-js-sdk/lib/crypto-api/recovery-key';
import type { IModuleViewModel } from '../shared/IModuleViewModel';
import type { IMatrixTimelineItem } from './MatrixTimelineItem';
import { MatrixTimelineItem } from './MatrixTimelineItem';
import * as matrixSdk from 'matrix-js-sdk';
import { EventTimeline, MatrixEvent, Room } from 'matrix-js-sdk';
import { Direction } from 'matrix-js-sdk/lib/models/event-timeline';
import { RoomEvent, ClientEvent, EventType } from 'matrix-js-sdk';
import { writable, type Writable } from 'svelte/store';
import { matrixSettings } from './MatrixSettings'; // Import the settings object
import { VerificationMethod } from 'matrix-js-sdk/lib/types'
import { logger } from 'matrix-js-sdk/lib/logger.js';

export interface MatrixMessage {
	id: string;
	sender: string;
	description: string;
	timestamp: number;
	isSelf: boolean;
}

export class MatrixViewModel implements IModuleViewModel {
  private static instance: MatrixViewModel;
  private client: matrixSdk.MatrixClient | null = null;
  private rooms: any[] = [];
  private sessionData: any = null;

  private outgoingMessageQueue: { roomId: string; eventType: string; content: any }[] = [];
  private isProcessingQueue = false;

  // NEW: track listener binding & start state (avoid client.clientRunning)
  private listenersBound = false;
  private started = false;
  private _timelineItems: Writable<IMatrixTimelineItem[]> = writable([]);
  private refreshTimer: any = null;
  private listRefreshInFlight = false;

  private hydrationState: 'idle' | 'syncing' | 'decrypting' | 'ready' = 'idle';
  private pendingLiveEvents: Array<{ ev: MatrixEvent; room: Room }> = [];

  private roomPaginationTokens: Map<string, string | null> = new Map();

  private constructor() {}

  public static getInstance(): MatrixViewModel {
	if (!MatrixViewModel.instance) {
	  MatrixViewModel.instance = new MatrixViewModel();
	}
	return MatrixViewModel.instance;
  }

  /**
   * Initialize client from restored session (if any) and start it cleanly.
   * - initialize crypto
   * - start client
   * - wait for PREPARED
   * - then do verification / backup checks and scrollback / decryption retries
   */
async initialize(): Promise<void> {
  console.log('Initializing MatrixViewModel...');
  (logger as any).setLevel("warn");
  this.sessionData = this.restoreSession();

  if (this.sessionData?.accessToken && this.sessionData.userId && this.sessionData.homeserverUrl) {
	const cryptoCallbacks: CryptoCallbacks = {};
	if (matrixSettings.recoveryKey?.trim()) {
	  (cryptoCallbacks as any).getSecretStorageKey = async ({ keys }: { keys: Record<string, any> }, name: string) => {
		const keyId = Object.keys(keys)[0];
		if (!keyId) return null;
		const decoded = await decodeRecoveryKey(matrixSettings.recoveryKey!.trim());
		return [keyId, decoded];
	  };
	}

	const clientOptions: matrixSdk.ICreateClientOpts = {
	  baseUrl: this.sessionData.homeserverUrl,
	  accessToken: this.sessionData.accessToken,
	  userId: this.sessionData.userId,
	  deviceId: this.sessionData.deviceId || undefined,
	  cryptoCallbacks,
	};

	this.client = matrixSdk.createClient(clientOptions);
	console.log('Matrix client created from restored session with crypto callbacks.');
  } else {
	console.log('No session data found. Client will be created upon login.');
	return; // nothing else to do until login()
  }

  if (!this.client) return;

  // ... your existing setup ...
  await this.client.initRustCrypto();
  this.setupEventListeners();

  if (!this.started) {
	await this.client.startClient();
	this.started = true;
  }

  this.hydrationState = 'syncing';
  await this.waitForPrepared();

  this.hydrationState = 'decrypting';
  await this.ensureVerificationAndKeys();
  await this.debugSecrets();
  await this.restoreFromRecoveryKey();
  await this.retryDecryptAllRooms();

  // initial list after decrypt attempts
  await this._fetchAndSetTimelineItems();

  // mark ready and release the buffer
  this.hydrationState = 'ready';
  await this.flushPendingLiveEvents();
}

  // Wait for the first PREPARED state
  private async waitForPrepared(): Promise<void> {
	if (!this.client) return;
	const c = this.client as any;
	const state = c.getSyncState?.();
	if (state === 'PREPARED') return;

	await new Promise<void>((resolve) => {
	  const onSync = (s: string) => {
		if (s === 'PREPARED') {
		  c.removeListener(ClientEvent.Sync, onSync);
		  resolve();
		}
	  };
	  c.on(ClientEvent.Sync, onSync);
	});
  }

  /**
   * Ensure we can get keys for old messages:
   * - try backup check/enable (restores if available using getSecretStorageKey)
   * - if device not verified, you can kick off requestOwnUserVerification()
   *   but DO NOT block initialize() here.
   */
  private async ensureVerificationAndKeys(): Promise<void> {
	if (!this.client) return;
	const crypto = this.client.getCrypto();
	if (!crypto) {
	  console.warn('Crypto not available; skipping ensureVerificationAndKeys');
	  return;
	}

	// Key backup restore (non-blocking; resolves when done)
	const { hasSSSS } = await this.hasSecretStorageAndBackup();
	try {
	  if (hasSSSS || matrixSettings.recoveryKey?.trim()) {
		// Only try to (enable/)use backup if we either have SSSS configured
		// or we can provide a recovery key
		await crypto.checkKeyBackupAndEnable();
		console.log('Key backup checked/enabled (or already ok).');
	  } else {
		console.log('[Backup] Skipping check/enable: no SSSS and no recovery key.');
	  }
	} catch (e) {
	  console.warn('Key backup enable/check failed (likely no SSSS / UIA required):', e);
	}

	// Verification status
	const userId = this.client.getUserId();
	const deviceId = this.client.getDeviceId();
	if (!userId || !deviceId) return;

	try {
	  const status = await crypto.getDeviceVerificationStatus(userId, deviceId);
	  if (!status?.signedByOwner) {
		console.warn('Device is unverified — prompting/initiating verification is recommended.');
		// You can start an own-user verification request like this:
		// const vreq = await crypto.requestOwnUserVerification();
		// (Do not block; wire to a UI flow.)
	  }
	} catch (e) {
	  console.warn('Failed to get device verification status:', e);
	}
  }

  /**
   * Retry decryption for all events in all rooms after keys are restored or shared.
   */
  public async retryDecryptAllRooms(): Promise<void> {
	if (!this.client) return;
	const rooms = this.client.getRooms() || [];
	for (const room of rooms) {
	  await this.retryDecryptAll(room);
	}
  }

  private getAllTimelines(room: matrixSdk.Room): matrixSdk.EventTimeline[] {
	const sets = room.getTimelineSets();                // EventTimelineSet[]
	const timelines: matrixSdk.EventTimeline[] = [];
	for (const ts of sets) timelines.push(...ts.getTimelines());  // EventTimeline[]
	return timelines;
  }

  private async retryDecryptAll(room: matrixSdk.Room): Promise<void> {
	if (!this.client) return;
	for (const tl of this.getAllTimelines(room)) {
	  for (const ev of tl.getEvents()) {
		try {
		  if (ev.isEncrypted() && !ev.getClearContent()) {
			console.log(`[Decrypt] Attempting to decrypt event ${ev.getId()} in room ${room.roomId}`);
			await this.client.decryptEventIfNeeded(ev);
			if (ev.getClearContent()) {
			  console.log(`[Decrypt] Successfully decrypted event ${ev.getId()} in room ${room.roomId}`);
			} else {
			  console.log(`[Decrypt] Event ${ev.getId()} in room ${room.roomId} still undecrypted after attempt.`);
			}
		  }
		} catch (e) {
		  console.warn(`[Decrypt] Failed to decrypt event ${ev.getId()} in room ${room.roomId}:`, e);
		}
	  }
	}
  }


  /**
   * Bootstraps SSSS / cross-signing / backup if needed.
   * NOTE: Avoid forcing bootstrap if the account already has SSSS/cross-signing.
   * Keep this optional and wrapped in try/catch to avoid blocking startup.
   */
  private async setupEncryptionSession(): Promise<void> {
	if (!this.client) return;
	const client = this.client;

	console.log('Setting up encryption session…');
	const crypto = client.getCrypto();
	if (!crypto) {
	  console.warn('Crypto not available. Skipping setupEncryptionSession.');
	  return;
	}

	// Try to bootstrap SSSS (safe to call; will no-op if already set)
	try {
	  // await crypto.bootstrapSecretStorage({}); // REMOVED: Only bootstrap if guiding user through SSSS setup
	  console.log('Secret storage bootstrapped or already present (skipped if no user guidance).');
	} catch (error) {
	  console.warn('bootstrapSecretStorage failed (may require UIA or already set):', error);
	}

	// Try to bootstrap cross-signing (safe if already configured)
	try {
	  await crypto.bootstrapCrossSigning({
		authUploadDeviceSigningKeys: async (makeRequest) => {
		  // If your HS requires UIA (password/SSO), provide it here.
		  await makeRequest({});
		},
	  });
	  console.log('Cross-signing bootstrapped or already present.');
	} catch (error) {
	  console.warn('bootstrapCrossSigning failed (likely UIA required or already present):', error);
	}

	// Attempt to enable backup (again)
	try {
	  await crypto.checkKeyBackupAndEnable();
	  console.log('Key backup checked/enabled.');
	} catch (error) {
	  console.warn('checkKeyBackupAndEnable failed:', error);
	}
  }

  public async restoreFromRecoveryKey() {
	if (!this.client) return;
	const crypto = this.client.getCrypto();
	if (!crypto) throw new Error("Crypto is not initialised on this client");

	const { hasSSSS, hasBackupSecret } = await this.hasSecretStorageAndBackup();

	// If there’s no SSSS/backup secret AND no recovery key, do nothing.
	if (!hasSSSS && !matrixSettings.recoveryKey?.trim()) {
	  console.log('[Backup] No SSSS and no recovery key → skipping restore.');
	  return;
	}

	// If we do have SSSS but not the backup secret, also skip quietly.
	if (hasSSSS && !hasBackupSecret && !matrixSettings.recoveryKey?.trim()) {
	  console.log('[Backup] SSSS exists but no m.megolm_backup.v1 secret → skipping restore.');
	  return;
	}

	// Proceed: ensure server info and enable backup if possible
	const check = await crypto.checkKeyBackupAndEnable().catch(() => null);
	if (!check) {
	  console.log('[Backup] No server backup or cannot enable → skipping restore.');
	  return;
	}

	const info = await crypto.getKeyBackupInfo();
	if (!info?.version) {
	  console.log('[Backup] Server backup lacks version → skipping restore.');
	  return;
	}

	// Load private key either from SSSS or directly from recovery key
	if (hasSSSS && hasBackupSecret) {
	  await crypto.loadSessionBackupPrivateKeyFromSecretStorage(); // may prompt callback ONLY if you registered it
	} else if (matrixSettings.recoveryKey?.trim()) {
	  const priv = await decodeRecoveryKey(matrixSettings.recoveryKey.trim());
	  await crypto.storeSessionBackupPrivateKey(priv, info.version);
	}

	const res = await crypto.restoreKeyBackup({
	  progressCallback: (p) => console.log("[Backup] restore:", p.stage),
	});
	console.log("[Backup] Restore result:", res);
  }

  private async debugSecrets(): Promise<void> {
	try {
	  const ss: any = (this.client as any).secretStorage;
	  if (!ss) { console.log('[SSSS] secretStorage undefined'); return; }
	  const defaultKey = await ss.getDefaultKeyId?.();
	  console.log('[SSSS] default key id =', defaultKey);
	  const hasBackupSecret = await ss.has?.('m.megolm_backup.v1');
	  console.log('[SSSS] has m.megolm_backup.v1 =', hasBackupSecret);
	} catch (e) {
	  console.warn('[SSSS] debug failed:', e);
	}
  }

  private async hasSecretStorageAndBackup(): Promise<{ hasSSSS: boolean; hasBackupSecret: boolean; }> {
	const ss: any = (this.client as any)?.secretStorage;
	if (!ss) return { hasSSSS: false, hasBackupSecret: false };
	const defaultKey = await ss.getDefaultKeyId?.();
	const hasSSSS = !!defaultKey;
	const hasBackupSecret = !!(await ss.has?.('m.megolm_backup.v1'));
	return { hasSSSS, hasBackupSecret };
  }

  public async verifyCurrentDevice(): Promise<void> {
  if (!this.client) {
	console.error("Cannot verify device: Matrix client not initialized.");
	return;
  }
  const crypto = this.client.getCrypto();
  if (!crypto) {
	console.error("Crypto not available; cannot verify device.");
	return;
  }

  const PhaseName: Record<number, string> = {
	[VerificationPhase.Unsent]: "Unsent",
	[VerificationPhase.Requested]: "Requested",
	[VerificationPhase.Ready]: "Ready",
	[VerificationPhase.Started]: "Started",
	[VerificationPhase.Cancelled]: "Cancelled",
	[VerificationPhase.Done]: "Done",
  };

  const waitForVerifier = (vreq: VerificationRequest, ms = 8000): Promise<Verifier> =>
	new Promise((resolve, reject) => {
	  if (vreq.verifier) return resolve(vreq.verifier);
	  let settled = false;
	  const onChange = () => {
		if (settled) return;
		if (vreq.verifier) {
		  settled = true;
		  vreq.off(VerificationRequestEvent.Change, onChange);
		  resolve(vreq.verifier);
		}
	  };
	  vreq.on(VerificationRequestEvent.Change, onChange);
	  const t = setTimeout(() => {
		if (settled) return;
		settled = true;
		vreq.off(VerificationRequestEvent.Change, onChange);
		reject(new Error("verifier not provided in time"));
	  }, ms);
	});

  const attachAndRunVerifier = (v: Verifier) => {
	v.on(VerifierEvent.ShowSas, async (sas: ShowSasCallbacks) => {
	  console.log("[SAS] Emoji:", sas.sas.emoji);
	  console.log("[SAS] Decimal:", sas.sas.decimal);
	  try {
		await sas.confirm();
		console.log("[SAS] Confirmed on this device.");
	  } catch (e) {
		console.error("[SAS] confirm() failed:", e);
		try { sas.cancel(); } catch {}
	  }
	});
	v.verify().catch((e) => console.error("[Verification] verifier.verify() error:", e));
  };

  console.log("[Verification] Bootstrapping secret storage (if not already).");
  // await crypto.bootstrapSecretStorage({}); // REMOVED: Only bootstrap if guiding user through SSSS setup

  console.log("[Verification] Requesting own user verification.");
  const vreq = await crypto.requestOwnUserVerification();

  let startedMethod = false;

  const waitForDone = new Promise<void>((resolve, reject) => {
	const onChange = async () => {
	  const phase = vreq.phase;
	  console.log("[Verification] Phase:", PhaseName[phase], phase);

	  // Requested → just wait (peer must accept). No accept() from our side.
	  if (phase === VerificationPhase.Requested) {
		console.log("[Verification] We initiated; waiting for peer to accept.");
		return;
	  }

	  // Ready/Started → kick off SAS or attach to existing verifier
	  if ((phase === VerificationPhase.Ready || phase === VerificationPhase.Started) && !startedMethod) {
		startedMethod = true;
		if (!vreq.verifier) {
		  try {
			console.log("[Verification] No verifier yet → starting SAS.");
			const v = await vreq.startVerification(VerificationMethod.Sas);
			attachAndRunVerifier(v);
			return;
		  } catch (e) {
			console.warn("[Verification] startVerification() failed (peer may have started):", e);
		  }
		}
		try {
		  const v = vreq.verifier ?? (await waitForVerifier(vreq, 8000));
		  console.log("[Verification] Verifier available; attaching handlers.");
		  attachAndRunVerifier(v);
		} catch (e) {
		  console.error("[Verification] Still no verifier after wait:", e);
		}
		return;
	  }

	  if (phase === VerificationPhase.Done) {
		console.log("[Verification] Completed ✅");
		vreq.off(VerificationRequestEvent.Change, onChange);
		resolve();

		await this.retryDecryptAllRooms();

		const rooms = this.client!.getRooms();
		if (rooms.length) {
		  await this.client!.scrollback(rooms[0]); // fetch older events
		  // Manually attempt decryption over the room’s timelines
		  const timelines = rooms[0].getLiveTimeline().getEvents();
		  for (const ev of timelines) {
			if (ev.isEncrypted() && !ev.getClearContent()) {
			  try { await this.client!.decryptEventIfNeeded(ev); } catch {}
			}
		  }
		}
		return;
	  }
	  if (phase === VerificationPhase.Cancelled) {
		const reason = (vreq as any).cancellationCode || "unknown";
		console.error("[Verification] Cancelled:", reason);
		vreq.off(VerificationRequestEvent.Change, onChange);
		reject(new Error(`Verification cancelled: ${reason}`));
	  }
	};

	vreq.on(VerificationRequestEvent.Change, onChange);
  });

  // Trigger handler once with current state
  (vreq as any).emit?.(VerificationRequestEvent.Change);

  // Timeout safety
  const TIMEOUT_MS = 2 * 60 * 1000;
  const withTimeout = new Promise<void>((resolve, reject) => {
	const t = setTimeout(() => reject(new Error("Verification timed out")), TIMEOUT_MS);
	waitForDone.then(
	  () => { clearTimeout(t); resolve(); },
	  (e) => { clearTimeout(t); reject(e); }
	);
  });

  try {
	console.log("[Verification] Waiting for completion…");
	await withTimeout;
	console.log("[Verification] Own user verification finished.");
  } catch (err) {
	console.error("[Verification] Failed:", err);
	try { await (vreq as any).cancel?.(); } catch {}
  }
}


  async login(homeserverUrl: string, username: string, password: string): Promise<void> {
	console.log(`Attempting to log in user: ${username} on homeserver: ${homeserverUrl}`);
	try {
	  // Stop old client if any
	  if (this.client && this.started) {
		await this.client.stopClient();
		this.started = false;
		this.listenersBound = false;
		this.client = null;
	  }

	  this.client = matrixSdk.createClient({ baseUrl: homeserverUrl });
	  const loginResponse = await this.client.login("m.login.password", {
		user: username,
		password,
	  });
	  this.client.setAccessToken(loginResponse.access_token);
	  console.log(`[Matrix] Login response: ${JSON.stringify(loginResponse)}`);

	  this.sessionData = {
		homeserverUrl,
		userId: loginResponse.user_id,
		accessToken: loginResponse.access_token,
		deviceId: loginResponse.device_id,
	  };
	  this.saveSession(this.sessionData);

	  // Re-run initialize with the new session (will start client, wait PREPARED, etc.)
	  await this.initialize();
	  console.log('Matrix login successful.');
	} catch (error) {
	  console.error('Matrix login failed:', error);
	  throw error;
	}
  }

  private saveSession(sessionData: any): void {
	console.log('Saving Matrix session data...');
	localStorage.setItem('matrixSession', JSON.stringify(sessionData));
  }

  private restoreSession(): any | null {
	console.log('Restoring Matrix session data...');
	const storedSession = localStorage.getItem('matrixSession');
	return storedSession ? JSON.parse(storedSession) : null;
  }

  public isLoggedIn(): boolean {
	return this.client !== null && this.client.isLoggedIn();
  }

  public getTimelineItems(): Writable<IMatrixTimelineItem[]> {
	return this._timelineItems;
  }

  private async _fetchAndSetTimelineItems(): Promise<void> {
	if (!this.client || !this.started || this.hydrationState !== 'ready') return;
	if (this.listRefreshInFlight) return;

	this.listRefreshInFlight = true;
	try {
	  const rooms = this.client.getRooms() ?? [];
	  const items = rooms.map((room) => {
		const live = room.getLiveTimeline().getEvents();
		const lastMsg = [...live].reverse().find((e) => e.getType() === EventType.RoomMessage);
		const description = lastMsg?.getContent()?.body ?? 'No recent messages';
		const timestamp = lastMsg?.getTs() ?? 0;
		return new MatrixTimelineItem({
		  id: room.roomId,
		  type: 'matrix',
		  title: room.name,
		  description,
		  timestamp,
		});
	  });

	  this._timelineItems.set(items);
	} finally {
	  this.listRefreshInFlight = false;
	}
  }

  private scheduleTimelineRefresh(delay = 200) {
	if (this.refreshTimer) clearTimeout(this.refreshTimer); // reset timer each call
	this.refreshTimer = setTimeout(async () => {
	  this.refreshTimer = null;
	  if (this.hydrationState !== 'ready' || this.listRefreshInFlight) return;

	  this.listRefreshInFlight = true;
	  try {
		await this._fetchAndSetTimelineItems();
	  } finally {
		this.listRefreshInFlight = false;
	  }
	}, delay);
  }

  getSettingsComponent(): any {
	return null;
  }

  getModuleName(): string {
	return 'Matrix';
  }

  async sendMessage(roomId: string, messageContent: string): Promise<void> {
	if (!this.client) {
	  console.error('Cannot send message: Matrix client not initialized.');
	  return;
	}
	const eventType = 'm.room.message';
	const content = { body: messageContent, msgtype: 'm.text' };
	this.enqueueMessage(roomId, eventType, content);
	this.processQueue();
  }

  private enqueueMessage(roomId: string, eventType: string, content: any): void {
	this.outgoingMessageQueue.push({ roomId, eventType, content });
	console.log(`Message enqueued for room ${roomId}. Queue size: ${this.outgoingMessageQueue.length}`);
  }

  private async processQueue(): Promise<void> {
	if (this.isProcessingQueue || !this.client || !this.client.isLoggedIn()) {
	  console.log('Skipping queue processing: already processing, client not ready, or not logged in.');
	  return;
	}

	this.isProcessingQueue = true;
	console.log(`Processing outgoing message queue. Current size: ${this.outgoingMessageQueue.length}`);

	while (this.outgoingMessageQueue.length > 0) {
	  const message = this.outgoingMessageQueue[0];
	  try {
		console.log(`Attempting to send message to room ${message.roomId}:`, message.content);
		await this.client.sendEvent(message.roomId, message.eventType as any, message.content);
		console.log(`Message sent successfully to room ${message.roomId}.`);
		this.outgoingMessageQueue.shift();
	  } catch (error) {
		console.error(`Failed to send message to room ${message.roomId}. Keeping in queue for retry:`, error);
		break;
	  }
	}
	this.isProcessingQueue = false;
	console.log(`Finished processing queue. Remaining size: ${this.outgoingMessageQueue.length}`);
  }

  public async getRoomMessages(
	roomId: string,
	fromToken: string | null,
	limit: number = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
	if (!this.client) throw new Error("Client not initialized");
	const room = this.client.getRoom(roomId);
	if (!room) return { messages: [], nextBatch: null };

	// INITIAL LOAD (no token) → use live timeline
	if (!fromToken) {
	  const live = room.getLiveTimeline();
	  const tokenB = live.getPaginationToken(EventTimeline.BACKWARDS);
	  const liveEvents = live.getEvents();

	  console.debug(
		`[VM][getRoomMessages:init] room=${roomId}, liveEvents=${liveEvents.length}, tokenB=${tokenB}`
	  );

	  for (const ev of liveEvents) {
		try {
		  await (this.client as any).decryptEventIfNeeded?.(ev);
		} catch {}
	  }

	  const messagesPromises = liveEvents
		.filter(
		  ev =>
			ev.getType() === "m.room.message" ||
			ev.getType() === "m.room.encrypted"
		)
		.map(ev => this.processMatrixEvent(ev, room));
	  const messages = (await Promise.all(messagesPromises)).filter(Boolean) as MatrixMessage[];

	  this.roomPaginationTokens.set(roomId, tokenB ?? null);

	  console.debug(
		`[VM][getRoomMessages:init] returning messages=${messages.length}, nextBatch=${tokenB}`
	  );
	  return { messages, nextBatch: tokenB ?? null };
	}

	// PAGINATION (older than fromToken) → call /messages
	console.debug(
	  `[VM][getRoomMessages:page] room=${roomId}, fromToken=${fromToken}, limit=${limit}`
	);

	const res = await this.client.createMessagesRequest(
	  roomId,
	  fromToken,
	  limit,
	  Direction.Backward,
	  undefined
	);

	// Reverse so chunk is oldest → newest
	const raw = (res?.chunk ?? []).slice().reverse();
	console.debug(
	  `[VM][getRoomMessages:page] /messages got chunk=${raw.length}, start=${res?.start}, end=${res?.end}`
	);

	const mapEvent = this.client.getEventMapper
	  ? this.client.getEventMapper()
	  : (e: any) => new MatrixEvent(e);

	const matrixEvents: MatrixEvent[] = raw.map(mapEvent);

	for (const ev of matrixEvents) {
	  try {
		await (this.client as any).decryptEventIfNeeded?.(ev);
	  } catch {}
	}

	const messagesPromises = matrixEvents
	  .filter(
		ev =>
		  ev.getType() === "m.room.message" ||
		  ev.getType() === "m.room.encrypted"
	  )
	  .map(ev => this.processMatrixEvent(ev, room));
	const messages = (await Promise.all(messagesPromises)).filter(
	  (m): m is MatrixMessage => Boolean(m)
	) as MatrixMessage[];

	const nextBatch = res?.end ?? null;
	this.roomPaginationTokens.set(roomId, nextBatch);

	console.debug(
	  `[VM][getRoomMessages:page] returning messages=${messages.length}, nextBatch=${nextBatch}`
	);
	return { messages, nextBatch };
  }

  // === Pagination Helper ===
  public async loadOlderMessages(
	roomId: string,
	fromToken?: string | null,
	limit: number = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
	const token = fromToken ?? this.roomPaginationTokens.get(roomId) ?? null;

	console.debug(
	  `[VM][loadOlderMessages] room=${roomId}, using fromToken=${token}, limit=${limit}`
	);
	if (!token) {
	  console.debug(`[VM][loadOlderMessages] no fromToken → nothing to load`);
	  return { messages: [], nextBatch: null };
	}

	const { messages, nextBatch } = await this.getRoomMessages(
	  roomId,
	  token,
	  limit
	);

	this.roomPaginationTokens.set(roomId, nextBatch);

	console.debug(
	  `[VM][loadOlderMessages] got messages=${messages.length}, nextBatch=${nextBatch}`
	);
	return { messages, nextBatch };
  }

  // === Token Reset ===
  public clearRoomPaginationTokens(roomId: string) {
	console.debug(`[VM][clearRoomPaginationTokens] room=${roomId}`);
	this.roomPaginationTokens.delete(roomId);
  }

	public getCurrentUserId(): string {
		return this.client?.getUserId() || 'unknown';
	}


  private async processMatrixEvent(event: matrixSdk.MatrixEvent, room: matrixSdk.Room): Promise<MatrixMessage | null> {
	if (!this.client) return null; // Ensure client is initialized to determine isSelf
	const currentUserId = this.client.getUserId();

	await this.client.decryptEventIfNeeded(event);

	if (event.getType() === EventType.RoomMessage) {
	  const content = event.getContent() ?? {};
	  const description = content.body ?? 'Undecryptable message or no body';
	  const timestamp = event.getTs();
	  const sender = event.getSender() ?? 'unknown sender'; // Provide a default value
	  const isSelf = sender === currentUserId;

	  return {
		id: event.getId() || `${Date.now()}-${Math.random()}`,
		sender,
		description,
		timestamp,
		isSelf,
	  };
	} else if (event.isDecryptionFailure()) {
	  // For decryption failures, we still want to show a message, but it won't be a "MatrixMessage" in the same sense.
	  // However, to satisfy the return type, we'll construct a basic MatrixMessage.
	  const sender = event.getSender() ?? 'unknown sender'; // Provide a default value
	  const isSelf = sender === currentUserId;
	  return {
		id: event.getId() || `${Date.now()}-${Math.random()}`,
		sender,
		description: 'This message could not be decrypted.',
		timestamp: event.getTs(),
		isSelf,
	  };
	}
	return null;
  }

  private async pushTimelineItemFromEvent(ev: MatrixEvent, room: Room) {
	if (!this.client) return;

	// Ensure we have cleartext if possible
	try { await this.client.decryptEventIfNeeded(ev); } catch {}

	let description = 'New room activity';
	if (ev.getContent()?.body) {
	  description = ev.getContent()?.body;
	} else if (ev.getContent()['m.relates_to'] && ev.getContent()['m.relates_to']?.rel_type === 'm.annotation') {
	  description = `${ev.sender?.name} reacted with ${ev.getContent()?.key}`;
	} else if (ev.getContent()['m.relates_to']?.rel_type === 'm.reference') {
	} else {
	  console.debug(`[VM][pushTimelineItemFromEvent] event=`, room.name || room.roomId, ev.getContent(), ev.sender?.name,` has no content, skipping`);
	  return;
	}


	const timestamp = ev.getTs() ?? Date.now();

	const id = room.roomId;                 // ✅ room-based identity
	const title = room.name || room.roomId; // ✅ show room name

	const updated = new MatrixTimelineItem({
	  id,
	  type: 'matrix',
	  title,
	  description,
	  timestamp,
	});

	this._timelineItems.update(items => {
	  const idx = items.findIndex(it => it.id === id);

	  if (idx === -1) {
		// New room card
		return [updated, ...items];
	  }

	  // Only update if this event is newer than what's displayed
	  const next = items.slice();
	  if ((next[idx]?.timestamp ?? 0) <= timestamp) {
		next[idx] = updated;
	  }
	  return next;
	});
  }

  private async flushPendingLiveEvents() {
	if (!this.pendingLiveEvents.length) return;
	// process in arrival order
	for (const { ev, room } of this.pendingLiveEvents) {
	  try { await this.pushTimelineItemFromEvent(ev, room); } catch {}
	}
	this.pendingLiveEvents.length = 0;
  }

  private setupEventListeners(): void {
	if (!this.client) {
	  console.error('Cannot set up event listeners: Matrix client is null.');
	  return;
	}
	if (this.listenersBound) return;
	this.listenersBound = true;

	this.client.on(RoomEvent.Timeline, async (event, room, toStartOfTimeline, removed) => {
	  if (toStartOfTimeline || removed || !room) return;

	  // If we are not fully hydrated yet, buffer and bail.
	  if (this.hydrationState !== 'ready') {
		this.pendingLiveEvents.push({ ev: event, room });
		return;
	  }

	  try {
		await this.pushTimelineItemFromEvent(event, room);
	  } catch (e) {
		console.warn('[RoomEvent.Timeline] push failed:', e);
	  }
	});

	this.client.on(ClientEvent.Sync, async (state) => {
	  console.log('Matrix ClientEvent.Sync state:', state);
	  console.log(`[ClientEvent.Sync] Sync state changed to: ${state}`);
	  if (state === 'PREPARED') {
		console.log('[ClientEvent.Sync] Client is PREPARED. Scheduling timeline refresh to include any new rooms.');
		this.scheduleTimelineRefresh(); // Update store after initial sync
		// process queue now that we likely have connectivity / initial sync
		this.processQueue();
	  }
	});

	this.client.on(ClientEvent.Room, async (room) => {
	//   console.log(`[ClientEvent.Room] New room detected: ID=${room.roomId}, Name="${room.name}". Re-fetching timeline items.`);
	  this.scheduleTimelineRefresh(500);
	});

	console.log('Matrix event listeners set up.');
  }

  public getOpenIdToken(): Promise<matrixSdk.IOpenIDToken> {
	return this.client!.getOpenIdToken();
  }
}
