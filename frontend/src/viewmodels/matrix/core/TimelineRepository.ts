import * as matrixSdk from 'matrix-js-sdk';

export interface RepoEvent {
  eventId: string;
  roomId: string;
  type: string; // SDK event.getType()
  sender: string;
  originServerTs: number;
  content: matrixSdk.IContent; // clear or encrypted content
  unsigned?: any;
}

export interface PageResult {
  events: RepoEvent[];
  fromToken: string | null;
  toToken: string | null; // next backward token
}

export interface TimelineRepositoryOptions {
  getClient: () => matrixSdk.MatrixClient | null;
  shouldIncludeEvent?: (ev: matrixSdk.MatrixEvent) => boolean;
  tryDecryptEvent?: (ev: matrixSdk.MatrixEvent) => Promise<void> | void;
  pageSize?: number; // default 20
}

type Tokens = { backward?: string | null };
type State = Map<string, Tokens>;

export class TimelineRepository {
  private state: State = new Map();
  private pageSize: number;

  constructor(private opts: TimelineRepositoryOptions) {
    this.pageSize = opts.pageSize ?? 20;
  }

  clearRoomState(roomId: string): void {
    this.state.delete(roomId);
  }

  private tokens(roomId: string): Tokens {
    if (!this.state.has(roomId)) this.state.set(roomId, {});
    return this.state.get(roomId)!;
  }

  /** Convert one SDK event → RepoEvent (with optional decrypt + filter) */
  async toRepoEvent(ev: matrixSdk.MatrixEvent): Promise<RepoEvent | null> {
    if (this.opts.shouldIncludeEvent && !this.opts.shouldIncludeEvent(ev)) return null;

    if (this.opts.tryDecryptEvent) {
      try {
        await this.opts.tryDecryptEvent(ev);
      } catch {
        /* ignore */
      }
    }

    return {
      eventId: ev.getId() ?? '',
      roomId: ev.getRoomId() ?? '',
      type: ev.getType(),
      sender: ev.getSender() ?? '',
      originServerTs: ev.getTs(),
      content: ev.getContent(),
      unsigned: ev.getUnsigned(),
    };
  }

  /** Initial page from the room's live timeline (no /messages yet). */
  async fetchInitial(roomId: string, pageSize = this.pageSize): Promise<PageResult> {
    const client = this.opts.getClient();
    if (!client) throw new Error('Matrix client not available');
    const room = client.getRoom(roomId);
    if (!room) return { events: [], fromToken: null, toToken: null };

    const live = room.getLiveTimeline();
    const all = live.getEvents();
    const pick = all.slice(-pageSize);

    const out: RepoEvent[] = [];
    for (const ev of pick) {
      const re = await this.toRepoEvent(ev);
      if (re) out.push(re);
    }

    // establish backward token from live timeline
    const bToken = live.getPaginationToken(matrixSdk.Direction.Backward) ?? null;
    this.tokens(roomId).backward = bToken;

    return { events: out, fromToken: null, toToken: bToken };
  }

  /** One backward page via room.paginateTimeline on live timeline. */
  async loadOlder(roomId: string, limit = this.pageSize): Promise<PageResult | null> {
    const client = this.opts.getClient();
    if (!client) throw new Error('Matrix client not available');
    const room = client.getRoom(roomId);
    if (!room) return null;

    const live = room.getLiveTimeline();
    const prevToken =
      live.getPaginationToken(matrixSdk.Direction.Forward) ?? this.tokens(roomId).backward ?? null;
    if (!prevToken) return null;

    // ✅ Use the client to paginate the EventTimeline
    const ok = await client.paginateEventTimeline(live, { backwards: true, limit });
    if (!ok) return null;

    // Newly loaded events are at the start of the live timeline window
    const windowEvents = live.getEvents().slice(0, limit);

    const converted: RepoEvent[] = [];
    for (const ev of windowEvents) {
      const re = await this.toRepoEvent(ev);
      if (re) converted.push(re);
    }

    const nextToken = live.getPaginationToken(matrixSdk.Direction.Backward) ?? null;
    this.tokens(roomId).backward = nextToken;

    return { events: converted, fromToken: prevToken, toToken: nextToken };
  }
}
