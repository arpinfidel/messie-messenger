import type { MatrixClient } from 'matrix-js-sdk';
import { MatrixDataLayer } from './MatrixDataLayer';

const DEFAULT_DIMS = { w: 32, h: 32, method: 'crop' as const };
type AvatarDims = typeof DEFAULT_DIMS;

/**
 * AvatarService centralizes all avatar logic (room + user), including
 * MXC resolution, composite avatar creation, and persistent caching.
 */
export class AvatarService {
  private compositeAvatarCache = new Map<string, string>(); // key: roomId|mxc1|mxc2 -> blob URL

  constructor(
    _ctx: { getClient: () => MatrixClient | null },
    private readonly data: MatrixDataLayer,
    _opts?: { maxMemEntries?: number; maxDbEntries?: number }
  ) {}

  async resolveUserAvatar(
    userId: string,
    dims: AvatarDims = DEFAULT_DIMS,
    opts?: { allowFallback?: boolean }
  ): Promise<string | undefined> {
    const allowFallback = opts?.allowFallback ?? true;
    const user = await this.data.getUser(userId).catch(() => undefined);
    const label = user?.displayName || userId;
    const resolved = await this.tryResolveMxc(this.userTag(userId), user?.avatarMxcUrl, dims);
    if (resolved) return resolved;

    if (!allowFallback) return undefined;
    return this.renderInitialsAvatar(label, userId, dims, 'user');
  }

  async resolveRoomAvatar(
    roomId: string,
    roomMxc?: string | null,
    dims: AvatarDims = DEFAULT_DIMS
  ): Promise<string | undefined> {
    const direct = await this.tryResolveMxc(this.roomTag(roomId), roomMxc ?? undefined, dims);
    if (direct) return direct;
    const currentUserId = this.data.getCurrentUserId();

    const key = `${roomId}`;
    const cached = this.compositeAvatarCache.get(key);
    if (cached) return cached;

    let members = await this.data.getRoomMembersSnapshot(roomId);
    if (!members.length) {
      members = await this.data.getRoomMembers(roomId);
    }
    const candidateMembers = this.pickRoomAvatarMembers(members, currentUserId);
    if (!candidateMembers.length) return this.createRoomInitialsAvatar(roomId, dims);

    const memberAvatars = (
      await Promise.all(
        candidateMembers.map((member) => this.resolveMemberAvatar(member, dims, false))
      )
    ).filter((url): url is string => !!url);

    if (memberAvatars.length === 1) return memberAvatars[0];

    if (memberAvatars.length > 1) {
      const composed = await this.composeBubbleAvatars(memberAvatars.slice(0, 3), dims.w, key);
      if (composed) {
        this.compositeAvatarCache.set(key, composed.url);
        return composed.url;
      }
      return memberAvatars[0];
    }

    return this.createRoomInitialsAvatar(roomId, dims);
  }

  // clear(): void {
  //   try {
  //     this.avatarResolver.clear();
  //   } catch {}
  //   for (const [, url] of this.compositeAvatarCache) {
  //     try {
  //       URL.revokeObjectURL(url);
  //     } catch {}
  //   }
  //   this.compositeAvatarCache.clear();
  // }

  // ---- helpers ----
  private async composeBubbleAvatars(
    urls: string[],
    size = 64,
    cacheKey?: string
  ): Promise<{ url: string; objectUrl: string } | undefined> {
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
      const objectUrl = URL.createObjectURL(blob);
      const fragment = cacheKey ? `composite=${encodeURIComponent(cacheKey)}` : 'composite';
      const tagged = this.tagUrl(objectUrl, fragment);
      return { url: tagged, objectUrl };
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

  private async createRoomInitialsAvatar(
    roomId: string,
    dims: AvatarDims
  ): Promise<string | undefined> {
    const room = await this.data.getRoom(roomId).catch(() => undefined);
    const label = room?.name || roomId;
    return this.renderInitialsAvatar(label, roomId, dims, 'room');
  }

  private async renderInitialsAvatar(
    label: string,
    seed: string,
    dims: AvatarDims,
    kind: 'user' | 'room'
  ): Promise<string | undefined> {
    try {
      const initials = this.computeInitials(label);
      const size = Math.max(16, Math.min(256, Math.floor(dims.w)) || 32);
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext('2d');
      if (!ctx) return undefined;
      ctx.fillStyle = this.colorFromId(seed);
      ctx.fillRect(0, 0, size, size);
      ctx.fillStyle = '#fff';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.font = `600 ${Math.floor(size * 0.55)}px system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif`;
      ctx.fillText(initials, size / 2, size / 2);
      const blob: Blob | null = await new Promise((resolve) =>
        canvas.toBlob((b) => resolve(b), 'image/png')
      );
      if (!blob) return undefined;
      const objectUrl = URL.createObjectURL(blob);
      const fragment =
        kind === 'room'
          ? `fallback=room-${encodeURIComponent(seed)}`
          : `fallback=user-${encodeURIComponent(seed)}`;
      return this.tagUrl(objectUrl, fragment);
    } catch {
      return undefined;
    }
  }

  private computeInitials(label: string): string {
    const words = label.trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) return '?';
    if (words.length === 1) {
      const [first] = words;
      return (first.slice(0, 2) || '?').toUpperCase();
    }
    return `${words[0][0]}${words[1][0]}`.toUpperCase();
  }

  private colorFromId(id: string): string {
    let hash = 0;
    for (let i = 0; i < id.length; i++) {
      hash = (hash << 5) - hash + id.charCodeAt(i);
      hash |= 0;
    }
    const hue = Math.abs(hash) % 360;
    const saturation = 60;
    const lightness = 50;
    return `hsl(${hue}deg ${saturation}% ${lightness}%)`;
  }

  private async resolveMemberAvatar(
    member: MemberCandidate,
    dims: AvatarDims,
    allowFallback: boolean
  ): Promise<string | undefined> {
    const user = await this.data.getUser(member.userId).catch(() => undefined);
    const label = user?.displayName || member.displayName || member.userId;
    for (const mxc of [user?.avatarMxcUrl, member.avatarUrl]) {
      const resolved = await this.tryResolveMxc(this.userTag(member.userId), mxc, dims);
      if (resolved) return resolved;
    }

    if (!allowFallback) return undefined;
    return this.renderInitialsAvatar(label, member.userId, dims, 'user');
  }

  private normalizeMember(member: any): MemberCandidate | undefined {
    const userId: string = member?.userId ?? '';
    if (!userId) return undefined;

    const displayName: string | undefined =
      member?.displayName ?? member?.name ?? member?.rawDisplayName ?? member?.user?.displayName;
    const membership: string | undefined = member?.membership;
    let avatarUrl: string | undefined = member?.avatarUrl ?? member?.avatarMxcUrl;
    if (!avatarUrl && typeof member?.getMxcAvatarUrl === 'function') {
      const mxc = member.getMxcAvatarUrl();
      if (mxc) avatarUrl = mxc;
    }
    return {
      userId,
      displayName,
      membership,
      avatarUrl,
    };
  }

  private userTag(userId: string): string {
    return `user-${encodeURIComponent(userId)}`;
  }

  private roomTag(roomId: string): string {
    return `room-${encodeURIComponent(roomId)}`;
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

  private async tryResolveMxc(
    tag: string,
    mxc: string | undefined,
    dims: AvatarDims
  ): Promise<string | undefined> {
    if (!mxc) return undefined;
    const result = await this.data.resolveAvatarMxc(mxc, dims, tag);
    if (!result.url) return undefined;

    const shouldKeep =
      (result.status >= 200 && result.status < 300) || (result.status > 0 && result.status < 400);
    if (shouldKeep && (await this.isRenderable(result.url))) return result.url;

    if (result.objectUrl) {
      try {
        URL.revokeObjectURL(result.objectUrl);
      } catch {}
    }
    if (shouldKeep) await this.data.invalidateAvatarMxc(mxc, dims);
    return undefined;
  }

  private pickRoomAvatarMembers(members: any[], currentUserId?: string | null): MemberCandidate[] {
    const seen = new Set<string>();
    return members
      .map((m) => this.normalizeMember(m))
      .filter((m): m is MemberCandidate => !!m && (m.membership || 'join') === 'join')
      .sort((a, b) => {
        const pref = (a.userId === currentUserId ? 1 : 0) - (b.userId === currentUserId ? 1 : 0);
        if (pref !== 0) return pref;
        return a.userId.localeCompare(b.userId);
      })
      .filter((member) => {
        if (member.userId === currentUserId || seen.has(member.userId)) return false;
        seen.add(member.userId);
        return true;
      })
      .slice(0, 3);
  }

  private async isRenderable(url: string): Promise<boolean> {
    try {
      await this.loadImage(url);
      return true;
    } catch {
      return false;
    }
  }
}

type MemberCandidate = {
  userId: string;
  membership?: string;
  displayName?: string;
  avatarUrl?: string;
};
