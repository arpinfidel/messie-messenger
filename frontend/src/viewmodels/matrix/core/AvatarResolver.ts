import type { MatrixClient } from 'matrix-js-sdk';

export type ResolveResult = {
  status: number;
  url?: string;
  bytes?: number;
  mime?: string;
  blob?: Blob;
  objectUrl?: string;
};

type MemEntry = {
  status: number;
  url?: string;
  objectUrl?: string;
  bytes?: number;
  mime?: string;
  ts: number;
};

export class AvatarResolver {
  private mem = new Map<string, MemEntry>();
  private inflight = new Map<string, Promise<ResolveResult>>();
  private readonly maxMemEntries: number;
  private readonly maxDbEntries: number;

  constructor(
    private readonly getClient: () => MatrixClient | null,
    opts?: { maxMemEntries?: number; maxDbEntries?: number }
  ) {
    this.maxMemEntries = opts?.maxMemEntries ?? 200;
    this.maxDbEntries = opts?.maxDbEntries ?? 200;
  }

  async resolve(
    mxc: string,
    dims = { w: 64, h: 64, method: 'crop' as const }
  ): Promise<ResolveResult> {
    const key = this.key(mxc, dims);
    const cached = this.mem.get(key);
    if (cached) {
      cached.ts = Date.now();
      return {
        status: cached.status,
        url: cached.url,
        bytes: cached.bytes,
        mime: cached.mime,
      };
    }
    const inflight = this.inflight.get(key);
    if (inflight) return inflight;

    const p = this.resolveInternal(mxc, dims)
      .then((result) => {
        if (result.url || result.status >= 400) {
          this.memSet(key, result);
        }
        return result;
      })
      .finally(() => this.inflight.delete(key));
    this.inflight.set(key, p);
    return p;
  }

  clear(): void {
    for (const [, e] of this.mem) {
      if (!e.objectUrl) continue;
      try {
        URL.revokeObjectURL(e.objectUrl);
      } catch {}
    }
    this.mem.clear();
    this.inflight.clear();
  }

  // ---- internals ----
  private async resolveInternal(
    mxc: string,
    dims: { w: number; h: number; method: 'scale' | 'crop' }
  ): Promise<ResolveResult> {
    const key = this.key(mxc, dims);

    const cli = this.getClient();
    if (!cli) return { status: 0 };
    const http = cli?.mxcUrlToHttp?.(mxc, dims.w, dims.h, dims.method, false, true, false);
    if (!http) return { status: 0 };

    try {
      const res = await fetch(http, { redirect: 'follow' });
      const status = res.status;
      if (!res.ok) {
        return { status };
      }
      const blob = await res.blob();
      const mime = blob.type || 'image/*';
      const objectUrl = URL.createObjectURL(blob);
      const url = this.tagUrl(objectUrl, `mxc=${encodeURIComponent(mxc)}`);
      return { status, url, blob, bytes: blob.size, mime, objectUrl };
    } catch {
      return { status: 0 };
    }
  }

  public key(mxc: string, dims: { w: number; h: number; method: 'scale' | 'crop' }): string {
    return `avatar|${mxc}|${dims.w}x${dims.h}|m=${dims.method}`;
  }

  private memSet(key: string, result: ResolveResult) {
    this.mem.set(key, {
      status: result.status,
      url: result.url,
      objectUrl: result.objectUrl,
      bytes: result.bytes,
      mime: result.mime,
      ts: Date.now(),
    });
    this.evictOldest();
  }

  private tagUrl(objectUrl: string, fragment: string): string {
    try {
      const url = new URL(objectUrl);
      url.hash = fragment;
      return url.toString();
    } catch {
      return `${objectUrl}#${fragment}`;
    }
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
