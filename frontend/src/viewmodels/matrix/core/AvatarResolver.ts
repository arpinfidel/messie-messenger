import type { MatrixClient } from 'matrix-js-sdk';
import { IndexedDbCache } from './IndexedDbCache';

type MemEntry = { url: string; ts: number; bytes: number; mime: string };

export class AvatarResolver {
  private mem = new Map<string, MemEntry>();
  private inflight = new Map<string, Promise<string | undefined>>();
  private db = new IndexedDbCache();
  private readonly maxMemEntries: number;
  private readonly maxDbEntries: number;

  constructor(
    private readonly getClient: () => MatrixClient | null,
    opts?: { maxMemEntries?: number; maxDbEntries?: number }
  ) {
    this.maxMemEntries = opts?.maxMemEntries ?? 200;
    this.maxDbEntries = opts?.maxDbEntries ?? 200;
  }

  async resolve(mxc: string, dims = { w: 64, h: 64, method: 'crop' as const }): Promise<string | undefined> {
    const key = this.key(mxc, dims);
    const cached = this.mem.get(key);
    if (cached) {
      cached.ts = Date.now();
      return cached.url;
    }
    const inflight = this.inflight.get(key);
    if (inflight) return inflight;

    const p = this.resolveInternal(mxc, dims)
      .then((url) => {
        if (url) this.memSet(key, url, 0, 'image/*');
        return url;
      })
      .finally(() => this.inflight.delete(key));
    this.inflight.set(key, p);
    return p;
  }

  async prefetch(mxc: string, dims = { w: 64, h: 64, method: 'crop' as const }): Promise<void> {
    try { await this.resolve(mxc, dims); } catch {}
  }

  clear(): void {
    for (const [, e] of this.mem) {
      try { URL.revokeObjectURL(e.url); } catch {}
    }
    this.mem.clear();
    this.inflight.clear();
  }

  // ---- internals ----
  private async resolveInternal(mxc: string, dims: { w: number; h: number; method: 'scale' | 'crop' }): Promise<string | undefined> {
    const key = this.key(mxc, dims);
    // try db first
    try {
      const rec = await this.db.getMedia(key);
      if (rec && rec.blob) {
        const url = URL.createObjectURL(rec.blob);
        this.memSet(key, url, rec.bytes, rec.mime);
        return url;
      }
    } catch {}

    const cli = this.getClient();
    if (!cli) return undefined;
    const http = (cli as any)?.mxcUrlToHttp?.(mxc, dims.w, dims.h, dims.method, false, true, false) as string | undefined;
    if (!http) return undefined;

    try {
      const res = await fetch(http, { redirect: 'follow' });
      if (!res.ok) return undefined; // avoid raw HTTP fallback
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      this.memSet(key, url, blob.size, blob.type || 'image/*');
      try {
        await this.db.putMedia({ key, ts: Date.now(), bytes: blob.size, mime: blob.type || 'image/*', blob });
        await this.db.pruneMedia(this.maxDbEntries);
      } catch {}
      return url;
    } catch {
      return undefined; // avoid raw HTTP fallback on network failures
    }
  }

  private key(mxc: string, dims: { w: number; h: number; method: 'scale' | 'crop' }): string {
    return `avatar|${mxc}|${dims.w}x${dims.h}|m=${dims.method}`;
    }

  private memSet(key: string, url: string, bytes: number, mime: string) {
    this.mem.set(key, { url, ts: Date.now(), bytes, mime });
    this.evictOldest();
  }

  private evictOldest() {
    const over = this.mem.size - this.maxMemEntries;
    if (over <= 0) return;
    const arr = Array.from(this.mem.entries());
    arr.sort((a, b) => a[1].ts - b[1].ts);
    for (let i = 0; i < over; i++) {
      const [k, e] = arr[i];
      // Do not revoke object URLs here to avoid breaking in-use <img> elements.
      this.mem.delete(k);
    }
  }
}
