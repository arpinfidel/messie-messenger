import { httpRequest } from '../http/base';

/** Fetch the IDs of rooms the user has joined. */
export async function joinedRooms(homeserverUrl: string, accessToken: string): Promise<string[]> {
  const res = await httpRequest(homeserverUrl, '/_matrix/client/v3/joined_rooms', {
    accessToken,
  });
  return Array.isArray(res?.joined_rooms) ? res.joined_rooms : [];
}

/**
 * Attempt to fetch a human-readable name for a room.
 *
 * Tries the following sources in order:
 *   1. `m.room.name` state event
 *   2. `m.room.canonical_alias` state event
 *   3. If `myUserId` is provided, derive from joined members (useful for DMs)
 */
export async function getRoomName(
  homeserverUrl: string,
  accessToken: string,
  roomId: string,
  myUserId?: string
): Promise<string | undefined> {
  // 1. Explicit room name
  try {
    const path = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/state/m.room.name`;
    const res = await httpRequest(homeserverUrl, path, { accessToken });
    if (typeof res?.name === 'string') {
      return res.name;
    }
  } catch {
    // 404 is expected for rooms without an explicit name
  }

  // 2. Canonical alias (often used for rooms without m.room.name)
  try {
    const path = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/state/m.room.canonical_alias`;
    const res = await httpRequest(homeserverUrl, path, { accessToken });
    if (typeof res?.alias === 'string') {
      return res.alias;
    }
  } catch {
    // ignore
  }

  // 3. Fallback to member heuristic for direct chats
  if (myUserId) {
    try {
      const members = await getRoomMembers(homeserverUrl, accessToken, roomId);
      const others = members.filter((m) => m.userId !== myUserId);
      if (others.length === 1) {
        return others[0].displayName || others[0].userId;
      }
      if (others.length > 1) {
        const names = others.map((m) => m.displayName || m.userId);
        if (names.length) return names.join(', ');
      }
    } catch {
      // ignore errors and fall through to undefined
    }
  }

  return undefined;
}

/**
 * Fetch joined rooms and derive human-readable names via a single /sync call.
 *
 * This mirrors the Matrix SDK approach by relying on:
 *   - state: m.room.name, m.room.canonical_alias
 *   - summary: m.heroes (other members) for DM-style naming
 *
 * Avoids per-room /state requests that often 404 for bridged DMs.
 */
export async function listJoinedRoomsWithNames(
  homeserverUrl: string,
  accessToken: string,
  myUserId?: string
): Promise<Array<{ id: string; name: string; heroes?: string[]; joinedCount?: number }>> {
  // Build a minimal filter: no timeline events, only limited state types, and include global account_data if needed later
  const filter = {
    room: {
      timeline: { limit: 0, types: [] as string[] },
      state: { types: ['m.room.name', 'm.room.canonical_alias'] as string[] },
      ephemeral: { not_types: ['*'] as string[] },
      account_data: { not_types: ['*'] as string[] },
      include_leave: false,
    },
    presence: { not_types: ['*'] as string[] },
    account_data: { types: ['m.direct'] as string[] },
  } as any;
  const qs = new URLSearchParams({ timeout: '0', filter: JSON.stringify(filter) });
  const path = `/_matrix/client/v3/sync?${qs.toString()}`;
  const res = await httpRequest(homeserverUrl, path, { accessToken });

  const joined: Record<string, any> = (res?.rooms?.join as any) || {};
  const rooms: Array<{ id: string; name: string; heroes?: string[]; joinedCount?: number }> = [];

  for (const [roomId, data] of Object.entries(joined)) {
    const stateEvents: any[] = Array.isArray((data as any)?.state?.events)
      ? (data as any).state.events
      : [];
    const summary: any = (data as any)?.summary || {};

    let name: string | undefined;

    // Prefer explicit m.room.name
    try {
      const nameEv = stateEvents.find((e) => e?.type === 'm.room.name' && e?.state_key === '');
      if (nameEv && typeof nameEv.content?.name === 'string' && nameEv.content.name) {
        name = nameEv.content.name;
      }
    } catch {}

    // Fallback to canonical alias
    if (!name) {
      try {
        const aliasEv = stateEvents.find(
          (e) => e?.type === 'm.room.canonical_alias' && e?.state_key === ''
        );
        const alias = aliasEv?.content?.alias;
        if (typeof alias === 'string' && alias) name = alias;
      } catch {}
    }

    // Fallback to heroes (DM-style). Use the first hero if available.
    const heroes: string[] = Array.isArray(summary?.['m.heroes']) ? summary['m.heroes'] : [];
    const joinedCount: number | undefined =
      typeof summary?.['m.joined_member_count'] === 'number'
        ? summary['m.joined_member_count']
        : undefined;
    if (!name) {
      const others = (heroes || []).filter((u) => !myUserId || u !== myUserId);
      if (others.length === 1 && joinedCount === 2) {
        // Likely a 1:1 — use the other member's mxid as a readable fallback
        name = others[0];
      } else if (others.length > 0) {
        // Group chat with multiple heroes — join a few mxids
        name = others.slice(0, 3).join(', ');
      }
    }

    rooms.push({ id: roomId, name: name || roomId, heroes, joinedCount });
  }
  return rooms;
}

/**
 * Fetch room membership events and map to lightweight member records.
 * Only joined members are returned.
 */
export async function getRoomMembers(
  homeserverUrl: string,
  accessToken: string,
  roomId: string
): Promise<Array<{ userId: string; displayName: string; avatarUrl?: string; membership?: string }>> {
  const qs = new URLSearchParams({ membership: 'join' });
  const path = `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/members?${qs.toString()}`;
  const res = await httpRequest(homeserverUrl, path, { accessToken });
  const events: any[] = Array.isArray(res?.chunk) ? res.chunk : [];
  const out: Array<{ userId: string; displayName: string; avatarUrl?: string; membership?: string }> = [];
  for (const ev of events) {
    if (ev?.type !== 'm.room.member') continue;
    const userId: string | undefined = typeof ev?.state_key === 'string' ? ev.state_key : undefined;
    if (!userId) continue;
    const content = ev?.content || {};
    const membership: string | undefined = typeof content?.membership === 'string' ? content.membership : undefined;
    if (membership && membership !== 'join') continue;
    const displayName: string = typeof content?.displayname === 'string' && content.displayname
      ? content.displayname
      : userId;
    const avatarUrl: string | undefined = typeof content?.avatar_url === 'string' && content.avatar_url
      ? content.avatar_url
      : undefined;
    out.push({ userId, displayName, avatarUrl, membership });
  }
  return out;
}
