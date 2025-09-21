import type { UpdateTodoItem } from '../../api/generated/models';

type SaveFn = (itemId: string, payload: UpdateTodoItem, signal?: AbortSignal) => Promise<void>;

type DebouncedFn = {
  (): void;
  cancel: () => void;
  flush: () => void;
};

function debounce<T extends (...args: any[]) => void>(fn: T, delay: number): DebouncedFn {
  let timeout: ReturnType<typeof setTimeout> | undefined;

  const debounced = (() => {
    if (timeout) clearTimeout(timeout);
    timeout = setTimeout(() => {
      timeout = undefined;
      fn();
    }, delay);
  }) as DebouncedFn;

  debounced.cancel = () => {
    if (!timeout) return;
    clearTimeout(timeout);
    timeout = undefined;
  };

  debounced.flush = () => {
    if (!timeout) return;
    clearTimeout(timeout);
    timeout = undefined;
    fn();
  };

  return debounced;
}

class SaveManager {
  private inFlight = new Map<string, { reqId: number; ctrl: AbortController }>();
  private nextId = new Map<string, number>();
  private queued = new Map<string, UpdateTodoItem>();
  private lastSent = new Map<string, string>();

  constructor(private performSave: SaveFn) {}

  enqueue(itemId: string, payload: UpdateTodoItem) {
    const encoded = JSON.stringify(payload);
    if (
      this.lastSent.get(itemId) === encoded &&
      !this.inFlight.has(itemId) &&
      !this.queued.has(itemId)
    ) {
      return;
    }
    this.queued.set(itemId, payload);
    if (!this.inFlight.has(itemId)) this.runNext(itemId);
  }

  cancel(itemId: string) {
    const current = this.inFlight.get(itemId);
    if (current) current.ctrl.abort();
    this.inFlight.delete(itemId);
    this.queued.delete(itemId);
  }

  private async runNext(itemId: string): Promise<void> {
    const nextPayload = this.queued.get(itemId);
    if (!nextPayload) return;

    const reqId = (this.nextId.get(itemId) ?? 0) + 1;
    this.nextId.set(itemId, reqId);
    this.queued.delete(itemId);

    const controller = new AbortController();
    this.inFlight.set(itemId, { reqId, ctrl: controller });

    try {
      await this.performSave(itemId, nextPayload, controller.signal);
      this.lastSent.set(itemId, JSON.stringify(nextPayload));
    } catch (error) {
      if ((error as any)?.name !== 'AbortError') {
        throw error;
      }
    } finally {
      const current = this.inFlight.get(itemId);
      if (!current || current.reqId !== reqId) return;
      this.inFlight.delete(itemId);
      if (this.queued.has(itemId)) this.runNext(itemId).catch(() => undefined);
    }
  }
}

export class DetailSaveQueue {
  private manager: SaveManager;
  private debouncers = new Map<string, DebouncedFn>();

  constructor(save: SaveFn) {
    this.manager = new SaveManager(save);
  }

  schedule(itemId: string, payload: UpdateTodoItem, delay = 400): void {
    const existing = this.debouncers.get(itemId);
    if (existing) existing.cancel();
    const debounced = debounce(() => this.manager.enqueue(itemId, payload), delay);
    this.debouncers.set(itemId, debounced);
    debounced();
  }

  cancel(itemId: string): void {
    const existing = this.debouncers.get(itemId);
    if (existing) {
      existing.cancel();
      this.debouncers.delete(itemId);
    }
    this.manager.cancel(itemId);
  }

  flushAll(onError?: (itemId: string, error: unknown) => void): void {
    for (const [itemId, debounced] of this.debouncers.entries()) {
      try {
        debounced.flush();
      } catch (error) {
        if (onError) onError(itemId, error);
      }
    }
    this.debouncers.clear();
  }
}
