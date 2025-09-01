import type { MatrixClient } from 'matrix-js-sdk';
import { AvatarResolver } from './AvatarResolver';
import { MatrixDataLayer } from './MatrixDataLayer';

/**
 * AvatarService centralizes all avatar logic (room + user), including
 * MXC resolution, composite avatar creation, and persistent caching.
 */
export class AvatarService {
  private avatarResolver: AvatarResolver;
  private compositeAvatarCache = new Map<string, string>(); // key: roomId|mxc1|mxc2 -> blob URL

  constructor(
    private readonly ctx: { getClient: () => MatrixClient | null },
    private readonly data: MatrixDataLayer,
    opts?: { maxMemEntries?: number; maxDbEntries?: number }
  ) {
    this.avatarResolver = new AvatarResolver(ctx.getClient, opts);
  }

  async resolveUserAvatar(
    userId: string,
    dims = { w: 32, h: 32, method: 'crop' as const }
  ): Promise<string | undefined> {
    try {
      const mxc = (await this.data.getUser(userId))?.avatarMxcUrl || undefined;
      if (!mxc) return undefined;
      return await this.data.resolveAvatarMxc(mxc, dims);
    } catch {
      return undefined;
    }
  }

  async resolveRoomAvatar(
    roomId: string,
    roomMxc?: string | null,
    dims = { w: 32, h: 32, method: 'crop' as const }
  ): Promise<string | undefined> {
    // If room has its own avatar, prefer it.
    if (roomMxc) {
      const url = await this.data.resolveAvatarMxc(roomMxc, dims);
      if (url) return url;
    }
    // Fallback: top 3 joined member avatars (prefer non-self), compose if multiple exist
    const members = await this.data.getRoomMembers(roomId);
    const currentUserId = this.data.getCurrentUserId();
    const sorted = members
      .filter((m) => (m.membership || 'join') === 'join')
      .sort((a, b) => {
        const pref = (a.userId === currentUserId ? 1 : 0) - (b.userId === currentUserId ? 1 : 0);
        if (pref !== 0) return pref;
        return a.userId.localeCompare(b.userId);
      });
    const mxcs: string[] = [];
    for (const m of sorted) {
      const user = await this.data.getUser(m.userId);
      const mxc = user?.avatarMxcUrl || undefined;
      if (mxc && !mxcs.includes(mxc)) mxcs.push(mxc);
      if (mxcs.length >= 3) break;
    }
    if (mxcs.length === 0) {
      return undefined;
    }
    if (mxcs.length === 1) return (await this.data.resolveAvatarMxc(mxcs[0], dims)) || undefined;

    // Compose N (2..3) avatars with stable layout seeded by room+mxcs
    const key = `${roomId}|${mxcs.sort().join('|')}`;
    const cached = this.compositeAvatarCache.get(key);
    if (cached) return cached;

    const urls = await Promise.all(mxcs.map((m) => this.data.resolveAvatarMxc(m, dims)));
    const resolved = urls.filter((u): u is string => !!u);
    if (resolved.length === 0) {
      return undefined;
    }
    if (resolved.length === 1) return resolved[0];
    const composed = await this.composeBubbleAvatars(resolved.slice(0, 3), dims.w);
    if (!composed) {
      return resolved[0];
    }
    this.compositeAvatarCache.set(key, composed.url);
    return composed.url;
  }

  clear(): void {
    try {
      this.avatarResolver.clear();
    } catch {}
    for (const [, url] of this.compositeAvatarCache) {
      try {
        URL.revokeObjectURL(url);
      } catch {}
    }
    this.compositeAvatarCache.clear();
  }

  // ---- helpers ----
  private async composeBubbleAvatars(
    urls: string[],
    size = 64
  ): Promise<{ url: string; blob: Blob } | undefined> {
    try {
      const imgs = await Promise.all(urls.map((u) => this.loadImage(u)));
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext('2d');
      if (!ctx) return undefined;
      ctx.clearRect(0, 0, size, size);

      // Static placements that look organic and fit inside square
      const n = Math.min(3, imgs.length);
      const positions: { x: number; y: number; r: number; img: HTMLImageElement }[] = [];
      if (n === 2) {
        const r = Math.floor(size * 0.32);
        positions.push({ x: Math.floor(size * 0.36), y: Math.floor(size * 0.44), r, img: imgs[0] });
        positions.push({ x: Math.floor(size * 0.64), y: Math.floor(size * 0.56), r, img: imgs[1] });
      } else {
        const r = Math.floor(size * 0.28);
        positions.push({ x: Math.floor(size * 0.34), y: Math.floor(size * 0.36), r, img: imgs[0] });
        positions.push({ x: Math.floor(size * 0.66), y: Math.floor(size * 0.4), r, img: imgs[1] });
        positions.push({ x: Math.floor(size * 0.5), y: Math.floor(size * 0.68), r, img: imgs[2] });
      }

      // Draw bubbles with thin black border
      for (const p of positions) {
        ctx.save();
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.closePath();
        ctx.clip();
        this.drawCover(ctx, p.img, p.x - p.r, p.y - p.r, p.r * 2, p.r * 2);
        ctx.restore();
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r - 0.5, 0, Math.PI * 2);
        ctx.closePath();
        ctx.lineWidth = 1;
        ctx.strokeStyle = '#000';
        ctx.stroke();
      }

      const blob: Blob | null = await new Promise((resolve) =>
        canvas.toBlob((b) => resolve(b), 'image/png')
      );
      if (!blob) return undefined;
      const url = URL.createObjectURL(blob);
      return { url, blob };
    } catch {
      return undefined;
    }
  }

  private loadImage(url: string): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => resolve(img);
      img.onerror = (e) => reject(e);
      img.src = url;
    });
  }

  private drawCover(
    ctx: CanvasRenderingContext2D,
    img: HTMLImageElement,
    dx: number,
    dy: number,
    dw: number,
    dh: number
  ) {
    // drawImage with cover behavior
    const iw = img.naturalWidth || img.width;
    const ih = img.naturalHeight || img.height;
    const targetRatio = dw / dh;
    const imgRatio = iw / ih;
    let sx = 0,
      sy = 0,
      sw = iw,
      sh = ih;
    if (imgRatio > targetRatio) {
      // Image is wider than target; crop sides
      sh = ih;
      sw = sh * targetRatio;
      sx = (iw - sw) / 2;
    } else {
      // Image is taller; crop top/bottom
      sw = iw;
      sh = sw / targetRatio;
      sy = (ih - sh) / 2;
    }
    ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
  }
}
