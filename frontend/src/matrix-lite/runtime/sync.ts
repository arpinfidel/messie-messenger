import { httpRequest } from '../http/base';

/**
 * Starts a minimal /sync loop that only fetches to_device events and device lists.
 * Returns a function to stop the loop.
 */
export function startMiniSync(
  homeserverUrl: string,
  accessToken: string,
  emit: (ev: any) => void,
  onSync?: (data: any) => void | Promise<void>
): () => void {
  let since: string | undefined;
  let stopped = false;

  async function loop(): Promise<void> {
    while (!stopped) {
      try {
        const filter = {
          room: { not_types: ['*'] },
          presence: { not_types: ['*'] },
          account_data: { not_types: ['*'] },
        } as any;
        const qs = new URLSearchParams({ timeout: '30000', filter: JSON.stringify(filter) });
        if (since) qs.set('since', since);
        const path = `/_matrix/client/v3/sync?${qs.toString()}`;
        const res = await httpRequest(homeserverUrl, path, { accessToken });
        if (typeof res?.next_batch === 'string') {
          since = res.next_batch;
        }
        let events: any[] | undefined;
        try {
          events = (await onSync?.(res)) || res?.to_device?.events;
        } catch (err) {
          console.warn('[matrix-lite] onSync error', err);
          events = res?.to_device?.events;
        }
        if (Array.isArray(events)) {
          for (const ev of events) {
            emit(ev);
          }
        }
      } catch (err) {
        console.warn('[matrix-lite] sync error', err);
        // Brief delay before retrying to avoid tight loop on failure
        await new Promise((r) => setTimeout(r, 2000));
      }
    }
  }
  loop();
  return () => {
    stopped = true;
  };
}
