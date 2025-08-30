import * as matrixSdk from 'matrix-js-sdk';
import { EventType, MatrixEvent, Room } from 'matrix-js-sdk';
import { writable, type Writable } from 'svelte/store';

import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixDataStore } from './core/MatrixDataStore';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import type { ImageContent, EncryptedFile } from 'matrix-js-sdk/lib/@types/media';

export interface MatrixMessage {
  id: string;
  sender: string;
  senderDisplayName: string; // Add this line
  description: string;
  timestamp: number;
  isSelf: boolean;
  msgtype?: string;
  imageUrl?: string;
  // For future enhancements/debugging
  mxcUrl?: string;
}

export class MatrixTimelineService {
  private _timelineItems: Writable<IMatrixTimelineItem[]> = writable([]);
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;
  private listRefreshInFlight = false;
  private pendingLiveEvents: Array<{ ev: MatrixEvent; room: Room }> = [];
  private imageBlobCache: Map<string, { url: string; ts: number; bytes: number; mime: string }> = new Map();
  private inflightImageResolvers: Map<string, Promise<string | undefined>> = new Map();
  private readonly imageCacheMaxEntries = 200;

  constructor(
    private readonly ctx: {
      getClient: () => matrixSdk.MatrixClient | null;
      isStarted: () => boolean;
      getHydrationState: () => 'idle' | 'syncing' | 'decrypting' | 'ready';
    },
    private readonly store: MatrixDataStore,
    private readonly layer: MatrixDataLayer
  ) {}

  private get client() {
    return this.ctx.getClient();
  }

  getTimelineItemsStore(): Writable<IMatrixTimelineItem[]> {
    return this._timelineItems;
  }

  /** Unified room list with their latest message preview.
   * Compute strictly from our MatrixDataStore instead of querying the SDK.
   */
  async fetchAndSetTimelineItems(): Promise<void> {
    if (!this.ctx.isStarted() || this.ctx.getHydrationState() !== 'ready') return;
    if (this.listRefreshInFlight) return;

    this.listRefreshInFlight = true;
    try {
      const rooms = this.store.getRooms();

      // Ensure at least one event (latest) is present to build previews.
      // Do this via the data layer, not by reading the SDK directly here.
      for (const r of rooms) {
        if (!this.store.getLatestEvent(r.id)) {
          try {
            await this.layer.fetchInitial(r.id, 1);
          } catch {}
        }
      }

      const items = rooms.map((room) => {
        const last = this.store.getLatestEvent(room.id);
        let description = 'No recent messages';
        // Prefer stored latestTimestamp (may be loaded from IndexedDB even if events tail is sparse)
        let timestamp = room.latestTimestamp || 0;
        if (last) {
          const preview = this.repoEventToPreview(last);
          description = preview.description;
          timestamp = last.originServerTs || timestamp || 0;
        }
        return new MatrixTimelineItem({
          id: room.id,
          type: 'matrix',
          title: room.name || room.id,
          description,
          timestamp,
        });
      });

      // Sort items by timestamp in descending order (latest first)
      items.sort((a, b) => b.timestamp - a.timestamp);
      this._timelineItems.set(items);
    } finally {
      this.listRefreshInFlight = false;
    }
  }

  scheduleTimelineRefresh(delay = 200) {
    if (this.refreshTimer) clearTimeout(this.refreshTimer);
    this.refreshTimer = setTimeout(async () => {
      this.refreshTimer = null;
      if (this.ctx.getHydrationState() !== 'ready' || this.listRefreshInFlight) return;

      this.listRefreshInFlight = true;
      try {
        await this.fetchAndSetTimelineItems();
      } finally {
        this.listRefreshInFlight = false;
      }
    }, delay);
  }

  /** Live pipeline: ingest event into store via data layer, then update preview. */
  async pushTimelineItemFromEvent(ev: MatrixEvent, room: Room) {
    await this.layer.ingestLiveEvent(ev, room);

    const last = this.store.getLatestEvent(room.roomId);
    const fallbackTs =
      this.store.getRooms().find((r) => r.id === room.roomId)?.latestTimestamp || 0;
    const timestamp = last?.originServerTs ?? fallbackTs;
    const id = room.roomId;
    const title = room.name || room.roomId;
    const { description } = last ? this.repoEventToPreview(last) : { description: '' };

    const updated = new MatrixTimelineItem({
      id,
      type: 'matrix',
      title,
      description,
      timestamp,
    });

    this._timelineItems.update((items) => {
      const idx = items.findIndex((it) => it.id === id);
      if (idx === -1) return [updated, ...items];
      const next = items.slice();
      if ((next[idx]?.timestamp ?? 0) <= timestamp) next[idx] = updated;
      return next;
    });
  }

  bufferLiveEvent(ev: MatrixEvent, room: Room) {
    this.pendingLiveEvents.push({ ev, room });
  }

  async flushPendingLiveEvents() {
    if (!this.pendingLiveEvents.length) return;
    for (const { ev, room } of this.pendingLiveEvents) {
      try {
        await this.pushTimelineItemFromEvent(ev, room);
      } catch {}
    }
    this.pendingLiveEvents.length = 0;
  }

  /* ---------------- Room messages API (delegates to repo) ---------------- */

  /** First page: from live timeline (repo.fetchInitial). */
  async getRoomMessages(
    roomId: string,
    fromToken: string | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    if (!fromToken) {
      const { events, toToken } = await this.layer.fetchInitial(roomId, limit);
      const messages = await this.mapRepoEventsToMessages(events);
      return { messages, nextBatch: toToken };
    }
    const page = await this.layer.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: await this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  async loadOlderMessages(
    roomId: string,
    fromToken?: string | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: string | null }> {
    // We ignore `fromToken` and use the store's backward token from live timeline.
    const page = await this.layer.loadOlder(roomId, limit);
    if (!page) return { messages: [], nextBatch: null };
    return { messages: await this.mapRepoEventsToMessages(page.events), nextBatch: page.toToken };
  }

  clearRoomPaginationTokens(roomId: string) {
    this.layer.clearRoom(roomId);
  }

  /* ---------------- Mapping helpers ---------------- */

  private async mapRepoEventsToMessages(events: RepoEvent[]): Promise<MatrixMessage[]> {
    const currentUserId = this.store.getCurrentUserId() ?? '';
    const msgs: MatrixMessage[] = [];
    const resolvers: Array<Promise<void>> = [];
    for (const re of events.filter(
      (re) => re.type === EventType.RoomMessage || re.type === 'm.room.encrypted'
    )) {
      const { description } = this.repoEventToPreview(re);
      const isSelf = re.sender === currentUserId;
      const senderDisplayName = re.sender; // Keep data-layer-only: avoid SDK lookup here
      const msgtype = re.content.msgtype;

      const msg: MatrixMessage = {
        id: re.eventId || `${Date.now()}-${Math.random()}`,
        sender: re.sender || 'unknown sender',
        senderDisplayName, // Assign display name
        description,
        timestamp: re.originServerTs || 0,
        isSelf,
        msgtype,
      };

      if (msgtype === matrixSdk.MsgType.Image) {
        const content = re.content as ImageContent;
        msg.mxcUrl = content.file?.url;
        const p = this.resolveEncryptedImageBlobUrl(content)
          .then((blobUrl) => {
            if (blobUrl) msg.imageUrl = blobUrl;
          })
          .catch(() => {});
        resolvers.push(p);
      }

      msgs.push(msg);
    }

    if (resolvers.length) await Promise.allSettled(resolvers);
    return msgs;
  }

  private async resolveEncryptedImageBlobUrl(content: ImageContent): Promise<string | undefined> {
    const cacheKey = this.computeImageCacheKey(content);
    const cached = cacheKey ? this.imageBlobCache.get(cacheKey) : undefined;
    if (cached) {
      cached.ts = Date.now();
      return cached.url;
    }
    if (cacheKey && this.inflightImageResolvers.has(cacheKey)) {
      return this.inflightImageResolvers.get(cacheKey)!;
    }

    const client = this.client;
    if (!client) return undefined;

    // Prefer thumbnail_file if present (smaller), else main file
    const encThumb = content.info?.thumbnail_file as EncryptedFile | undefined;
    const enc = encThumb ?? content.file;
    if (!enc) {
      // Unencrypted image fallback
      if (content.url) {
        const http = client.mxcUrlToHttp(content.url, 1024, 1024, 'scale', false, true, false);
        return http || undefined;
      }
      return undefined;
    }

    // Build authenticated media URL (download, not thumbnail) for ciphertext
    const url = client.mxcUrlToHttp(
      enc.url,
      undefined,
      undefined,
      undefined,
      false,
      undefined,
      true
    );
    const token = client.getAccessToken();
    if (!url) return undefined;

    const headers: Record<string, string> = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;

    const resolver = (async () => {
      try {
      const res = await fetch(url, { headers, redirect: 'follow' });
      if (!res.ok) return undefined;
      const cipherBuf = await res.arrayBuffer();

      // Optional integrity check: verify ciphertext SHA-256 matches provided hash
      const expectedHash = enc.hashes?.sha256;
      if (typeof expectedHash === 'string' && expectedHash.length > 0) {
        const digest = await crypto.subtle.digest('SHA-256', cipherBuf);
        const got = this.toBase64Unpadded(new Uint8Array(digest));
        if (got !== this.normalizeBase64(expectedHash)) {
          return undefined; // hash mismatch
        }
      }

      // Import JWK and decrypt (AES-CTR, 256-bit). IV is 16-byte unpadded base64.
      const jwk = enc.key as JsonWebKey;
      const key = await crypto.subtle.importKey('jwk', jwk, { name: 'AES-CTR' }, false, [
        'decrypt',
      ]);
      const ivBytes = this.fromBase64Unpadded(enc.iv);
      if (ivBytes.length !== 16) return undefined;
      // Copy into a Uint8Array backed by an ArrayBuffer (satisfies BufferSource typing)
      const counter = new Uint8Array(16);
      counter.set(ivBytes);
      const plainBuf = await crypto.subtle.decrypt(
        { name: 'AES-CTR', counter, length: 64 },
        key,
        cipherBuf
      );

      const mime = content.info?.mimetype || 'application/octet-stream';
      const blob = new Blob([plainBuf], {
        type: typeof mime === 'string' ? mime : 'application/octet-stream',
      });
      const blobUrl = URL.createObjectURL(blob);
      if (cacheKey) {
        this.imageBlobCache.set(cacheKey, {
          url: blobUrl,
          ts: Date.now(),
          bytes: (plainBuf as ArrayBuffer).byteLength,
          mime: typeof mime === 'string' ? mime : 'application/octet-stream',
        });
        this.evictOldImageBlobs();
      }
      return blobUrl;
    } catch {
      return undefined;
    }
    })();

    if (cacheKey) this.inflightImageResolvers.set(cacheKey, resolver);
    try {
      return await resolver;
    } finally {
      if (cacheKey) this.inflightImageResolvers.delete(cacheKey);
    }
  }

  // ---- Base64 helpers (unpadded, url-safe handling) ----
  private normalizeBase64(s: string): string {
    // convert base64url -> base64 and strip padding for comparison
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

  private computeImageCacheKey(content: ImageContent): string | undefined {
    const thumb = content.info?.thumbnail_file as EncryptedFile | undefined;
    const file = thumb ?? (content.file as EncryptedFile | undefined);
    if (file?.url) {
      const hash = file.hashes?.sha256 ? this.normalizeBase64(file.hashes.sha256) : '';
      const tag = thumb ? 't' : 'f';
      return `enc|${tag}|${file.url}|sha256=${hash}`;
    }
    if (content.url) {
      return `plain|${content.url}|w=1024|h=1024|m=scale`;
    }
    return undefined;
  }

  private evictOldImageBlobs(): void {
    const over = this.imageBlobCache.size - this.imageCacheMaxEntries;
    if (over <= 0) return;
    const entries = Array.from(this.imageBlobCache.entries());
    entries.sort((a, b) => a[1].ts - b[1].ts);
    for (let i = 0; i < over; i++) {
      const [key, entry] = entries[i];
      try { URL.revokeObjectURL(entry.url); } catch {}
      this.imageBlobCache.delete(key);
    }
  }

  /** Create a human preview from RepoEvent content (works for decrypted encrypted). */
  private repoEventToPreview(re: RepoEvent): { description: string } {
    const c = re.content;
    if (c.msgtype === matrixSdk.MsgType.Image) {
      const body = c.body;
      return { description: `Image: ${typeof body === 'string' ? body : 'Image'}` };
    }
    const body = c.body;
    if (typeof body === 'string') return { description: body };

    const relates = c['m.relates_to'];
    if (relates?.rel_type === 'm.annotation') {
      const key = typeof c.key === 'string' ? (c.key as string) : undefined;
      if (key) return { description: `${re.sender} reacted with ${key}` };
    }
    if (relates?.rel_type === 'm.reference') {
      return { description: 'Replied to a message' };
    }
    return { description: 'This message could not be decrypted.' };
  }
}
