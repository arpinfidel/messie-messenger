// frontend/src/lib/matrix/MatrixViewModel.ts
import { type CryptoCallbacks, type Verifier, VerifierEvent, VerificationPhase, VerificationRequestEvent, type VerificationRequest, type ShowSasCallbacks } from 'matrix-js-sdk/lib/crypto-api';
import { decodeRecoveryKey } from 'matrix-js-sdk/lib/crypto-api/recovery-key';
import type { IModuleViewModel } from '../shared/IModuleViewModel';
import type { IMatrixTimelineItem } from './MatrixTimelineItem';
import { MatrixTimelineItem } from './MatrixTimelineItem';
import * as matrixSdk from 'matrix-js-sdk';
import { RoomEvent, ClientEvent, EventType } from 'matrix-js-sdk';
import { writable, type Writable } from 'svelte/store';
import { matrixSettings } from './MatrixSettings'; // Import the settings object
import { VerificationMethod } from 'matrix-js-sdk/lib/types'

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
    this.sessionData = this.restoreSession();

    if (this.sessionData?.accessToken && this.sessionData.userId && this.sessionData.homeserverUrl) {
      const cryptoCallbacks: CryptoCallbacks = {
        // FIXED: robust SSSS key retrieval (uses your correct recovery key)
        getSecretStorageKey: async ({ keys }, name) => {
          const keyId = Object.keys(keys)[0];
          console.log('[SSSS] requested name=', name, 'keys=', Object.keys(keys));
          if (!keyId) return null;
          const recoveryKey = matrixSettings.recoveryKey; // Use recovery key from settings
          if (!recoveryKey) {
            console.warn('[SSSS] No recovery key provided in settings.');
            return null;
          }
          const decoded = await decodeRecoveryKey(recoveryKey.trim());
          console.log('[SSSS] returning key for keyId=', keyId);
          return [keyId, decoded];
        },
      };

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

    // --- STARTUP ORDER FIX ---
    await this.client.initRustCrypto();
    console.log('Rust crypto initialized.');

    this.setupEventListeners(); // guard inside to avoid duplicates

    // Start once
    if (!this.started) {
      await this.client.startClient();
      this.started = true;
      console.log('Matrix client started.');
      await this._fetchAndSetTimelineItems(); // Initial fetch
    }

    // Wait until PREPARED before touching rooms/scrollback
    await this.waitForPrepared();
    console.log('Client sync is PREPARED. Initial sync complete.');
    await this.client.getCrypto()!.bootstrapSecretStorage({})

    // Don’t throw on unverified; allow runtime to fetch/restore keys.
    await this.ensureVerificationAndKeys();

    // Debug secrets
    await this.debugSecrets();

    // Force a backup restore right after PREPARED
    await this.restoreFromRecoveryKey();
    await this.retryDecryptAllRooms();
    console.log('[_fetchAndSetTimelineItems] Re-fetching timeline items after decryption retries.');
    await this._fetchAndSetTimelineItems(); // Re-fetch after decryption attempts
  }

  // Wait for the first PREPARED state
  private async waitForPrepared(): Promise<void> {
    if (!this.client) return;
    const c = this.client;

    // If already PREPARED, resolve immediately (e.g., on re-init)
    let prepared = false;
    const immediate = new Promise<void>((resolve) => {
      c.on(ClientEvent.Sync, function onSync(state: string) {
        if (state === 'PREPARED') {
          prepared = true;
          c.removeListener(ClientEvent.Sync, onSync as any);
          resolve();
        }
      });
    });

    // Small race guard: if a previous PREPARED already happened in this session,
    // the handler above will never fire. In practice, PREPARED should happen once,
    // so we still rely on the event. If you maintain your own sync-state flag, check it here.

    await immediate;
    if (!prepared) {
      console.warn('waitForPrepared: PREPARED may have been reached earlier.');
    }
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
    try {
      console.log('Checking/enabling key backup…');
      await crypto.checkKeyBackupAndEnable();
      console.log('Key backup checked/enabled (or already ok).');
    } catch (e) {
      console.warn('Key backup enable/check failed (may require UIA or no backup exists):', e);
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
      await crypto.bootstrapSecretStorage({});
      console.log('Secret storage bootstrapped or already present.');
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

    // const recoveryKey = matrixSettings.recoveryKey;
    // if (!recoveryKey) {
    //   console.log('[Backup] No recovery key provided in settings. Skipping direct restore attempts.');
    //   return;
    // }

    // console.log("[Backup] Restoring with recovery KEY (direct)...", recoveryKey);

    // 0) Force-refresh server info and (re-)enable backup if possible
    const check = await crypto.checkKeyBackupAndEnable(); // returns null if no backup
    if (!check) throw new Error("No key backup on server");

    // 1) Confirm the server’s active version
    const info = await crypto.getKeyBackupInfo();
    if (!info?.version) throw new Error("Backup present but no version reported");
    console.log("[Backup] Server active version:", info);

    // 2) (Optional) See why it’s “not trusted”
    const trust = await crypto.isKeyBackupTrusted(info);
    console.log("[Backup] Trust:", trust);

    // 3) Verify our recovery key actually matches the server’s public key
    // const priv = decodeRecoveryKey(recoveryKey);            // bytes
    // await crypto.storeSessionBackupPrivateKey(priv, info.version); // note: include version
    // console.log("[Backup] Stored private key for version", info.version);
    await crypto.loadSessionBackupPrivateKeyFromSecretStorage()

    // 4) Try the restore against the *server’s* active version
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
  await crypto.bootstrapSecretStorage({});

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

        // Call re-decryption and timeline refresh methods
        await this.retryDecryptAllRooms();
        await this._fetchAndSetTimelineItems();
        // debug
        const roomsss = await this.client?.getRooms();
        const resss = await this.client?.scrollback(roomsss![0]);
        await resss?.decryptAllEvents();
         
          // Retrieve events from the room's live timeline after scrollback
          const events: matrixSdk.MatrixEvent[] = resss!.getLiveTimeline().getEvents();
          console.log("events", events)
          console.log("decrypting events")
          for (const event of events) {
              if (event.isEncrypted() && !event.isDecryptionFailure()) {
                  await this.client!.decryptEventIfNeeded(event);
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
      const loginResponse = await this.client.loginRequest({
        type: "m.login.password",
        user: username,
        password,
      });
      this.client.setAccessToken(loginResponse.access_token);

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
    if (!this.client || !this.started) {
      console.warn('Matrix client not ready to fetch timeline items.');
      this._timelineItems.set([]);
      return;
    }

    const rooms = this.client.getRooms();
    console.log(`[_fetchAndSetTimelineItems] Total rooms retrieved: ${rooms ? rooms.length : 0}`);
    if (!rooms) {
      this._timelineItems.set([]);
      return;
    }

    const items = rooms.map((room) => {
      console.log(`[_fetchAndSetTimelineItems] Processing room: ID=${room.roomId}, Name="${room.name}", Encrypted=${room.hasEncryptionStateEvent()}`);
      // FIXED: use live timeline for last message
      const live = room.getLiveTimeline().getEvents();
      console.log(`[_fetchAndSetTimelineItems] Room ${room.roomId} has ${live.length} live timeline events.`);
      const lastMsg = [...live].reverse().find((e) => e.getType() === EventType.RoomMessage);
      if (lastMsg) {
        console.log(`[_fetchAndSetTimelineItems] Last message found for room ${room.roomId}.`);
      } else {
        console.log(`[_fetchAndSetTimelineItems] No last message found for room ${room.roomId}.`);
      }
      const description = lastMsg?.getContent()?.body ?? 'No recent messages';
      const timestamp = lastMsg?.getTs() ?? Date.now(); // Changed to number

      return new MatrixTimelineItem({
        id: room.roomId,
        type: 'matrix',
        title: room.name,
        description,
        timestamp,
      });
    });
    this._timelineItems.set(items);
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

  async getRoomMessages(roomId: string): Promise<IMatrixTimelineItem[]> {
    if (!this.client || !this.client.isLoggedIn()) {
      console.error('Cannot get room messages: Matrix client not initialized or not logged in.');
      throw new Error('Matrix client not ready.');
    }

    const room = this.client.getRoom(roomId);
    if (!room) throw new Error(`Room ${roomId} not found.`);

    console.log(`Fetching messages for room: ${roomId}`);
    const items: IMatrixTimelineItem[] = [];

    try {
      // First, read current live events
      const live = room.getLiveTimeline().getEvents();
      for (const ev of live) {
        const item = this.processMatrixEvent(ev, room);
        if (item) items.push(item);
      }

      // Scroll back (updates timeline in-place; no chunks returned)
      await this.client.scrollback(room, 100);

      // Re-read timeline after scrollback
      const live2 = room.getLiveTimeline().getEvents();
      for (const ev of live2) {
        const item = this.processMatrixEvent(ev, room);
        if (item) items.push(item);
      }

      // Sort by ts
      items.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

      // Attempt another decrypt-pass after scrollback (in case keys arrived)
      await this.retryDecryptAll(room);

      return items;
    } catch (error) {
      console.error(`Error fetching messages for room ${roomId}:`, error);
      throw new Error(`Failed to retrieve messages for room ${roomId}.`);
    }
  }

  private processMatrixEvent(event: matrixSdk.MatrixEvent, room: matrixSdk.Room): IMatrixTimelineItem | null {
    if (event.getType() === EventType.RoomMessage) {
      const content = event.getContent() ?? {};
      const description = content.body ?? 'Undecryptable message or no body';
      const timestamp = event.getTs();

      return new MatrixTimelineItem({
        id: event.getId() || `${Date.now()}-${Math.random()}`,
        type: 'matrix',
        title: room?.name || 'Unknown Room',
        description,
        timestamp,
        sender: event.getSender(),
        rawData: event.event,
      });
    } else if (event.isDecryptionFailure()) {
      return new MatrixTimelineItem({
        id: event.getId() || `${Date.now()}-${Math.random()}`,
        type: 'matrix',
        title: room?.name || 'Unknown Room',
        description: 'This message could not be decrypted.',
        timestamp: event.getTs(), // Changed to number
        sender: event.getSender(),
        rawData: event.event,
      });
    }
    return null;
  }

  private setupEventListeners(): void {
    if (!this.client) {
      console.error('Cannot set up event listeners: Matrix client is null.');
      return;
    }
    if (this.listenersBound) return;
    this.listenersBound = true;

    this.client.on(RoomEvent.Timeline, (event, room, toStartOfTimeline, removed) => {
      if (toStartOfTimeline || removed) return;
      if (!room) return;

      const timelineItem = this.processMatrixEvent(event, room);
      if (timelineItem) {
        console.log('New MatrixTimelineItem:', timelineItem);
        // TODO: push into your reactive store
      }
    });

    this.client.on(ClientEvent.Sync, async (state) => {
      console.log('Matrix ClientEvent.Sync state:', state);
      console.log(`[ClientEvent.Sync] Sync state changed to: ${state}`);
      if (state === 'PREPARED') {
        console.log('[ClientEvent.Sync] Client is PREPARED. Re-fetching timeline items to include any new rooms.');
        await this._fetchAndSetTimelineItems(); // Update store after initial sync
        // process queue now that we likely have connectivity / initial sync
        this.processQueue();

        // debug
        try{
          await this.retryDecryptAllRooms();
          const rooms = this.client!.getRooms();
          console.log("rooms", rooms);
          const roomId = '!nvq1hSoAZf8CP6cH7JE7:beeper.local';
          const room = this.client!.getRoom(roomId);
          await this.client?.scrollback(room!, 100);
          
          // Retrieve events from the room's live timeline after scrollback
          const events: matrixSdk.MatrixEvent[] = room!.getLiveTimeline().getEvents();
          console.log("events", events)
          console.log("decrypting events")
          for (const event of events) {
              if (event.isEncrypted() && !event.isDecryptionFailure()) {
                  await this.client!.decryptEventIfNeeded(event);
              }
          }
        } catch (e) {
          console.error(e)
        }
        // end debug
      }
    });

    this.client.on(ClientEvent.Room, async (room) => {
      console.log(`[ClientEvent.Room] New room detected: ID=${room.roomId}, Name="${room.name}". Re-fetching timeline items.`);
      await this._fetchAndSetTimelineItems();
    });

    console.log('Matrix event listeners set up.');
  }
}
