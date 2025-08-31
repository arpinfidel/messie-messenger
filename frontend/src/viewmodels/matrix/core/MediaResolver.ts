import type { MatrixClient } from 'matrix-js-sdk';
import type { EncryptedFile, ImageContent } from 'matrix-js-sdk/lib/@types/media';

type BlobEntry = { url: string; ts: number; bytes: number; mime: string };

export class MediaResolver {
  private cache: Map<string, BlobEntry> = new Map();
  private inflight: Map<string, Promise<string | undefined>> = new Map();
  private readonly maxEntries: number;

  constructor(
    private readonly getClient: () => MatrixClient | null,
    opts?: { maxEntries?: number }
  ) {
    this.maxEntries = opts?.maxEntries ?? 200;
  }

  async resolveImage(content: ImageContent, dims = { w: 1024, h: 1024, method: 'scale' as const }): Promise<string | undefined> {
    const key = this.computeKeyForImage(content, dims);
    const cached = key ? this.cache.get(key) : undefined;
    if (cached) {
      cached.ts = Date.now();
      return cached.url;
    }
    if (key && this.inflight.has(key)) return this.inflight.get(key)!;

    const promise = this.resolveImageInternal(content, dims).then((url) => {
      if (url && key) {
        // We can’t know bytes here reliably without reading the blob again; store 0.
        this.cache.set(key, { url, ts: Date.now(), bytes: 0, mime: content.info?.mimetype || 'application/octet-stream' });
        this.evictOldest();
      }
      return url;
    });
    if (key) this.inflight.set(key, promise);
    try {
      return await promise;
    } finally {
      if (key) this.inflight.delete(key);
    }
  }

  clear(): void {
    for (const [, entry] of this.cache) {
      try { URL.revokeObjectURL(entry.url); } catch {}
    }
    this.cache.clear();
    this.inflight.clear();
  }

  // ---- internals ----
  private async resolveImageInternal(content: ImageContent, dims: { w: number; h: number; method: 'scale' | 'crop' }): Promise<string | undefined> {
    const client = this.getClient();
    if (!client) return undefined;

    // Prefer encrypted thumbnail if present, else main file
    const encThumb = content.info?.thumbnail_file as EncryptedFile | undefined;
    const enc = encThumb ?? content.file;
    if (!enc) {
      // Unencrypted image
      if (content.url) {
        return (
          client.mxcUrlToHttp(content.url, dims.w, dims.h, dims.method, false, true, false) ||
          undefined
        );
      }
      return undefined;
    }

    return this.decryptToBlobUrl(enc, content.info?.mimetype);
  }

  private async decryptToBlobUrl(enc: EncryptedFile, mimeHint?: string): Promise<string | undefined> {
    const client = this.getClient();
    if (!client) return undefined;
    const url = client.mxcUrlToHttp(enc.url, undefined, undefined, undefined, false, undefined, true);
    if (!url) return undefined;

    const token = client.getAccessToken();
    const headers: Record<string, string> = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;

    try {
      const res = await fetch(url, { headers, redirect: 'follow' });
      if (!res.ok) return undefined;
      const cipherBuf = await res.arrayBuffer();

      const expectedHash = enc.hashes?.sha256;
      if (typeof expectedHash === 'string' && expectedHash.length > 0) {
        const digest = await crypto.subtle.digest('SHA-256', cipherBuf);
        const got = this.toBase64Unpadded(new Uint8Array(digest));
        if (got !== this.normalizeBase64(expectedHash)) return undefined;
      }

      const jwk = enc.key as JsonWebKey;
      const key = await crypto.subtle.importKey('jwk', jwk, { name: 'AES-CTR' }, false, ['decrypt']);
      const ivBytes = this.fromBase64Unpadded(enc.iv);
      if (ivBytes.length !== 16) return undefined;
      const counter = new Uint8Array(16);
      counter.set(ivBytes);
      const plainBuf = await crypto.subtle.decrypt({ name: 'AES-CTR', counter, length: 64 }, key, cipherBuf);

      const mime = typeof mimeHint === 'string' ? mimeHint : 'application/octet-stream';
      const blob = new Blob([plainBuf], { type: mime });
      return URL.createObjectURL(blob);
    } catch {
      return undefined;
    }
  }

  private computeKeyForImage(content: ImageContent, dims: { w: number; h: number; method: 'scale' | 'crop' }): string | undefined {
    const enc = (content.info?.thumbnail_file as EncryptedFile | undefined) ?? (content.file as EncryptedFile | undefined);
    if (enc?.url) {
      const hash = enc.hashes?.sha256 ? this.normalizeBase64(enc.hashes.sha256) : '';
      return `enc|${enc.url}|sha256=${hash}`;
    }
    if (content.url) {
      return `plain|${content.url}|w=${dims.w}|h=${dims.h}|m=${dims.method}`;
    }
    return undefined;
  }

  private evictOldest(): void {
    const over = this.cache.size - this.maxEntries;
    if (over <= 0) return;
    const entries = Array.from(this.cache.entries());
    entries.sort((a, b) => a[1].ts - b[1].ts);
    for (let i = 0; i < over; i++) {
      const [key, entry] = entries[i];
      try { URL.revokeObjectURL(entry.url); } catch {}
      this.cache.delete(key);
    }
  }

  // ---- Base64 helpers ----
  private normalizeBase64(s: string): string {
    return s.replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/, '');
  }
  private toBase64Unpadded(bytes: Uint8Array): string {
    let binary = '';
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return btoa(binary).replace(/=+$/, '');
  }
  private fromBase64Unpadded(s: string): Uint8Array {
    const base64 = this.normalizeBase64(s);
    const padded = base64 + '='.repeat((4 - (base64.length % 4 || 4)) % 4);
    const binary = atob(padded);
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out;
  }
}

