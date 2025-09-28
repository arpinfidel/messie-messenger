import { describe, expect, test, vi, beforeEach } from 'vitest';

const startupSpy = vi.fn();
const createClientSpy = vi.fn();

class MockCrypto {
  checkKeyBackupAndEnable = vi.fn().mockResolvedValue(undefined);
  getDeviceVerificationStatus = vi.fn().mockResolvedValue({} as any);
  bootstrapCrossSigning = vi.fn().mockResolvedValue(undefined);
  getKeyBackupInfo = vi.fn().mockResolvedValue({ version: '1' });
  loadSessionBackupPrivateKeyFromSecretStorage = vi.fn().mockResolvedValue(undefined);
  storeSessionBackupPrivateKey = vi.fn().mockResolvedValue(undefined);
  restoreKeyBackup = vi.fn().mockResolvedValue({} as any);
  requestOwnUserVerification = vi.fn().mockResolvedValue({} as any);
  exportRoomKeys = vi.fn().mockResolvedValue([{ room_id: '!room:server', session_id: 'sess' }]);
}

class MockClient {
  public crypto = new MockCrypto();
  public started = false;
  public syncState: string | null = null;
  private listeners = new Map<string, Set<(...args: any[]) => void>>();

  startClient = vi.fn(async () => {
    this.started = true;
  });
  stopClient = vi.fn(async () => {
    this.started = false;
  });

  isLoggedIn = vi.fn(() => true);
  getUserId = vi.fn(() => '@user:server');
  getDeviceId = vi.fn(() => 'DEVICE');
  getAccessToken = vi.fn(() => 'token');
  isInitialSyncComplete = vi.fn(() => this.syncState === 'PREPARED');
  getSyncState = vi.fn(() => this.syncState);
  decryptEventIfNeeded = vi.fn(async () => undefined);
  sendEvent = vi.fn(async () => ({ event_id: '$event' }));
  uploadContent = vi.fn(async () => ({ content_uri: 'mxc://server/id' }));
  isRoomEncrypted = vi.fn(() => true);
  mxcUrlToHttp = vi.fn(() => 'https://cdn');
  encryptAttachment = vi.fn(async () => ({ data: new ArrayBuffer(0), file: {} }));
  getCrypto = vi.fn(() => this.crypto);
  secretStorage = {
    getDefaultKeyId: vi.fn(async () => 'key'),
    has: vi.fn(async () => true),
  };

  on(event: string, listener: (...args: any[]) => void) {
    const set = this.listeners.get(event) ?? new Set();
    set.add(listener);
    this.listeners.set(event, set);
  }

  removeListener(event: string, listener: (...args: any[]) => void) {
    this.listeners.get(event)?.delete(listener);
  }

  emit(event: string, ...payload: any[]) {
    this.listeners.get(event)?.forEach((cb) => cb(...payload));
  }
}

vi.mock('matrix-js-sdk', async () => {
  const actual = await vi.importActual<any>('matrix-js-sdk');
  return {
    ...actual,
    ClientEvent: { ...actual.ClientEvent, Sync: 'sync' },
    IndexedDBStore: class {
      async startup() {
        startupSpy();
      }
    },
    MemoryStore: class {
      startup() {
        startupSpy();
      }
    },
    createClient: (...args: any[]) => {
      createClientSpy(...args);
      return new MockClient();
    },
  };
});

vi.mock('matrix-js-sdk/lib/crypto-api/recovery-key', () => ({
  decodeRecoveryKey: vi.fn(async () => new Uint8Array([1, 2, 3])),
}));

import { JsMatrixRuntimeAdapter } from '@/viewmodels/matrix/core/runtime/adapters/JsMatrixRuntimeAdapter';
import { matrixNative } from '@/plugins/matrixNative';
import {
  exportJsCryptoBundle,
  pullBundleFromNative,
  pushBundleToNative,
} from '@/viewmodels/matrix/core/runtime/cryptoTransfer';
import { ClientEvent } from 'matrix-js-sdk';

describe('JsMatrixRuntimeAdapter', () => {
  beforeEach(() => {
    startupSpy.mockClear();
    createClientSpy.mockClear();
  });

  test('creates matrix client from session', async () => {
    const adapter = new JsMatrixRuntimeAdapter();
    await adapter.init({
      session: {
        homeserverUrl: 'https://matrix.org',
        userId: '@user:matrix.org',
        accessToken: 'abc',
        deviceId: 'DEVICE',
      },
      getRecoveryKey: () => 'recovery',
    });

    expect(createClientSpy).toHaveBeenCalledTimes(1);
    const opts = createClientSpy.mock.calls[0][0];
    expect(opts.baseUrl).toBe('https://matrix.org');
    expect(opts.accessToken).toBe('abc');
    expect(opts.userId).toBe('@user:matrix.org');
    expect(opts.deviceId).toBe('DEVICE');
    expect(opts.store).toBeDefined();
  });

  test('facade proxies lifecycle and crypto calls', async () => {
    const adapter = new JsMatrixRuntimeAdapter();
    await adapter.init({ homeserverUrl: 'https://matrix' });
    const client = adapter.getClient();
    expect(client).not.toBeNull();

    await client!.startClient();
    expect((createClientSpy.mock.results[0].value as MockClient).startClient).toHaveBeenCalled();

    const wait = client!.waitForSync('PREPARED');
    const concrete = createClientSpy.mock.results[0].value as MockClient;
    concrete.syncState = 'PREPARED';
    concrete.emit((ClientEvent as any).Sync ?? 'sync', 'PREPARED');
    await wait;

    const crypto = client!.getCrypto();
    expect(crypto).not.toBeNull();
    await crypto!.checkKeyBackupAndEnable();
    expect(concrete.crypto.checkKeyBackupAndEnable).toHaveBeenCalled();
  });
});

describe('MatrixNative web mock', () => {
  test('tracks session state', async () => {
    await matrixNative.initFromSession({
      session: {
        homeserverUrl: 'https://example.org',
        userId: '@user:example.org',
        accessToken: 'token',
      },
    });
    let state = await matrixNative.currentState();
    expect(state.hasSession).toBe(true);
    expect(state.started).toBe(false);
    await matrixNative.start();
    state = await matrixNative.currentState();
    expect(state.started).toBe(true);
    await matrixNative.stop();
    state = await matrixNative.currentState();
    expect(state.started).toBe(false);
  });
});

describe('crypto transfer helpers', () => {
  test('exports JS crypto bundle and round-trips via native mock', async () => {
    const adapter = new JsMatrixRuntimeAdapter();
    await adapter.init({ homeserverUrl: 'https://matrix' });
    const client = adapter.getClient()?.asMatrixClient?.() as MockClient;
    const bundle = await exportJsCryptoBundle(client);
    expect(bundle.roomKeys?.length).toBe(1);
    await pushBundleToNative(bundle);
    const restored = await pullBundleFromNative();
    expect(restored?.roomKeys?.length).toBe(1);
  });
});
