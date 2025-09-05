import {
  initAsync,
  OlmMachine,
  UserId,
  DeviceId,
  DeviceLists,
} from '@matrix-org/matrix-sdk-crypto-wasm';

let machine: OlmMachine | null = null;

export async function initCrypto(userId: string, deviceId: string): Promise<void> {
  if (machine) return;
  await initAsync();
  machine = await OlmMachine.initialize(new UserId(userId), new DeviceId(deviceId));
  console.log('[matrix-lite] crypto engine initialized');
}

export function getOlmMachine(): OlmMachine | null {
  return machine;
}

export async function handleSync(data: any): Promise<void> {
  if (!machine || !data) return;
  try {
    const toDevice = JSON.stringify(data.to_device?.events || []);
    const changed = (data.device_lists?.changed || []).map((u: string) => new UserId(u));
    const left = (data.device_lists?.left || []).map((u: string) => new UserId(u));
    const deviceLists = new DeviceLists(changed, left);
    const otk = new Map<string, number>();
    const counts = data.device_one_time_keys_count as Record<string, number> | undefined;
    if (counts) {
      for (const [k, v] of Object.entries(counts)) {
        otk.set(k, v);
      }
    }
    const unused = Array.isArray(data.device_unused_fallback_key_types)
      ? new Set<string>(data.device_unused_fallback_key_types)
      : undefined;
    await machine.receiveSyncChanges(toDevice, deviceLists, otk, unused);
  } catch (err) {
    console.warn('[matrix-lite] crypto sync error', err);
  }
}
