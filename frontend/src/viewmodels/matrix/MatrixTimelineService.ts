import * as matrixSdk from 'matrix-js-sdk';
import { EventType, MatrixEvent, Room } from 'matrix-js-sdk';
import { writable, type Writable, get } from 'svelte/store';

import { MatrixTimelineItem, type IMatrixTimelineItem } from './MatrixTimelineItem';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import type { ImageContent } from 'matrix-js-sdk/lib/@types/media';
import { MediaResolver } from './core/MediaResolver';
import { AvatarService } from './core/AvatarService';
import type { INotificationService } from '@/notifications/NotificationService';
import { matrixSettings } from './MatrixSettings';

export interface MatrixMessage {
  id: string;
  sender: string;
  senderDisplayName: string; // Add this line
  senderAvatarUrl?: string;
  body: string;
  timestamp: number;
  isSelf: boolean;
  msgtype?: string;
  imageUrl?: string;
  fileUrl?: string;
  fileName?: string;
  // For future enhancements/debugging
  mxcUrl?: string;
}

export class MatrixTimelineService {
  private _timelineItems: Writable<IMatrixTimelineItem[]> = writable([]);
  private nextTimeline: IMatrixTimelineItem[] = [];
  private flushTimeout: ReturnType<typeof setTimeout> | null = null;
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;
  private pendingLiveEvents: Array<{ ev: MatrixEvent; room: Room }> = [];
  private mediaResolver = new MediaResolver(() => this.client);
  private readonly maxRooms = 30; // limit room list to most recent N
  // Invalidate counter to notify UI when async media resolves
  private mediaVersion: Writable<number> = writable(0);
  private notifications?: INotificationService;
  private lastNotifyByRoom = new Map<string, number>();

  constructor(
    private readonly ctx: {
      getClient: () => matrixSdk.MatrixClient | null;
      isStarted: () => boolean;
      getHydrationState: () => 'idle' | 'syncing' | 'decrypting' | 'ready';
    },
    private readonly data: MatrixDataLayer,
    private readonly avatars: AvatarService,
    notifications?: INotificationService
  ) {
    this.handleEvent();
    this.notifications = notifications;
  }

  private get client() {
    return this.ctx.getClient();
  }

  getTimelineItemsStore(): Writable<IMatrixTimelineItem[]> {
    return this._timelineItems;
  }

  getMediaVersionStore(): Writable<number> {
    return this.mediaVersion;
  }

  private bumpMediaVersion() {
    this.mediaVersion.update((n) => n + 1);
  }

  async initTimeline(): Promise<void> {
    const rooms = await this.data.getRooms();
    // Sort rooms by latest activity and keep only top N
    const sortedRooms = rooms
      .slice()
      .sort((a, b) => (b.latestTimestamp ?? 0) - (a.latestTimestamp ?? 0));
    const limitedRooms = sortedRooms.slice(0, this.maxRooms);

    const items: IMatrixTimelineItem[] = [];
    const currentItems = this.nextTimeline;
    const currentItemsByID = new Map(currentItems.map((it) => [it.id, it]));

    for (const room of limitedRooms) {
      const lastEvent = (await this.data.getRoomEvents(room.id, null, 1, true)).events[0];
      let description = 'No recent messages';
      let timestamp = room.latestTimestamp || 0;
      if (lastEvent) {
        const preview = this.repoEventToPreview(lastEvent);
        description = preview.description;
        timestamp = lastEvent.originServerTs || timestamp || 0;
      }
      // get previous avatar if available
      let avatarUrl: string | undefined = currentItemsByID.get(room.id)?.avatarUrl;

      items.push(
        new MatrixTimelineItem({
          id: room.id,
          type: 'matrix',
          title: room.name || room.id,
          description,
          avatarUrl,
          timestamp,
          unreadCount: room.unreadCount || 0,
        })
      );
    }

    // for all timeline items, if new timestamp is older than existing, keep existing
    // else replace
    // if new item not in existing, add
    for (const newItem of items) {
      const existingIdx = this.nextTimeline.findIndex((it) => it.id === newItem.id);
      if (existingIdx === -1) {
        this.nextTimeline.push(newItem);
      } else if ((this.nextTimeline[existingIdx]?.timestamp ?? 0) <= newItem.timestamp) {
        this.nextTimeline[existingIdx] = newItem;
      }
    }

    // Resolve avatars in background with limited concurrency and patch items as they arrive
    const maxConcurrent = 6;
    let i = 0;
    const work = async () => {
      try {
        while (i < limitedRooms.length) {
          const idx = i++;
          const room = limitedRooms[idx];
          const url = await this.avatars.resolveRoomAvatar(room.id, room.avatarMxcUrl, {
            w: 64,
            h: 64,
            method: 'crop',
          });
          // No 'continue' here, allow fallback avatar
          const existingItem = this.nextTimeline.find((t) => t.id === room.id);
          if (!existingItem) {
            continue;
          }

          const updated = new MatrixTimelineItem({
            id: existingItem.id,
            type: existingItem.type,
            title: existingItem.title,
            description: existingItem.description,
            timestamp: existingItem.timestamp,
            avatarUrl: url || existingItem.avatarUrl, // Use new URL or fallback to existing
          });

          this.bufferTimelineUpdate(updated);
          this.scheduleFlush();
        }
      } catch (e) {
        console.warn('Error resolving room avatar:', e);
      }
    };
    // Kick off workers without awaiting completion
    for (let k = 0; k < Math.min(maxConcurrent, limitedRooms.length); k++) {
      work();
    }
  }

  /** Live pipeline: ingest event into store via data layer, then update preview. */
  async handleEvent() {
    // await this.data.ingestLiveEvent(ev, room);
    this.data.onRepoEvent(async (ev, room, meta) => {
      const rooms = await this.data.getRoom(room.roomId);
      const fallbackTs = rooms?.latestTimestamp || 0;
      const unreadCount = rooms?.unreadCount || 0;
      const timestamp = ev?.originServerTs ?? fallbackTs;
      const id = room.roomId;
      const title = room.name || room.roomId;
      const { description } = ev ? this.repoEventToPreview(ev) : { description: '' };
      const body = typeof ev?.content?.body === 'string' ? (ev!.content.body as string) : undefined;

      let avatarUrl: string | undefined;
      const roomMxc = room.getMxcAvatarUrl();
      avatarUrl = await this.avatars.resolveRoomAvatar(room.roomId, roomMxc || undefined, {
        w: 64,
        h: 64,
        method: 'crop',
      });

      const updated = new MatrixTimelineItem({
        id,
        type: 'matrix',
        title,
        description,
        // Keep previous avatar if resolve failed
        avatarUrl:
          avatarUrl ||
          (get(this._timelineItems).find((it) => it.id === id) as IMatrixTimelineItem | undefined)
            ?.avatarUrl,
        timestamp,
        unreadCount,
      });

      // Apply buffered update before scheduling a flush
      this.bufferTimelineUpdate(updated);

      // Only show notifications when:
      // - a notification service is configured
      // - the event is a user message and not sent by self
      // - Matrix push rules say this event should notify
      if (
        this.notifications &&
        meta?.isLive &&
        ev?.type === 'm.room.message' &&
        ev.sender !== this.client?.getUserId()
      ) {
        // Suppress notifications when the app tab is active/visible
        const isVisible =
          typeof document !== 'undefined' && document.visibilityState === 'visible';
        const hasFocus =
          typeof document !== 'undefined' &&
          typeof document.hasFocus === 'function' &&
          document.hasFocus();
        const suppress = isVisible && hasFocus;

        if (!suppress) {
          // Per-room notification cooldown
          const now = Date.now();
          const cooldownMs = Math.max(0, Number(matrixSettings.notifyCooldownMs) || 0);
          const last = this.lastNotifyByRoom.get(id) || 0;
          if (cooldownMs > 0 && now - last < cooldownMs) {
            // Skip due to cooldown window
            this.scheduleFlush();
            return;
          }
          try {
            const client = this.client;
            const mxEv = room.findEventById(ev.eventId);
            const actions = mxEv && client?.getPushActionsForEvent(mxEv);
            if (actions?.notify) {
              void this.notifications.notify({
                title,
                body: body ?? description,
                icon: avatarUrl,
              });
              this.lastNotifyByRoom.set(id, now);
            }
          } catch (err) {
            console.warn('[MatrixTimelineService] notify failed', err);
          }
        }
      }
      this.scheduleFlush();
    });

    // Reflect unread updates from the data layer into the UI.
    this.data.onUnreadChange((roomId, unread) => {
      this.setRoomUnread(roomId, unread);
    });
  }

  bufferTimelineUpdate(ev: MatrixTimelineItem) {
    const idx = this.nextTimeline.findIndex((it) => it.id === ev.id);
    if (idx === -1) {
      this.nextTimeline.push(ev);
    } else if ((this.nextTimeline[idx]?.timestamp ?? 0) <= ev.timestamp) {
      this.nextTimeline[idx] = ev;
    }
  }

  setRoomUnread(roomId: string, unreadCount: number) {
    const existing = this.nextTimeline.find((it) => it.id === roomId);
    if (!existing) return;
    const updated = new MatrixTimelineItem({
      id: existing.id,
      type: existing.type,
      title: existing.title,
      description: existing.description,
      avatarUrl: existing.avatarUrl,
      timestamp: existing.timestamp,
      rawData: (existing as any).rawData,
      sender: (existing as any).sender,
      unreadCount,
    });
    this.bufferTimelineUpdate(updated);
    this.scheduleFlush();
  }

  async flushTimeline() {
    this._timelineItems.set(this.nextTimeline);
  }

  async scheduleFlush() {
    if (this.flushTimeout) return;
    this.flushTimeout = setTimeout(() => {
      this.flushTimeline();
      this.flushTimeout = null;
    }, 100);
  }

  /* ---------------- Room messages API (delegates to repo) ---------------- */

  /** First page: from live timeline when fromToken is null, otherwise older page. */
  async getRoomMessages(
    roomId: string,
    beforeTS: number | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: number | null }> {
    const { events, firstTS } = await this.data.getRoomEvents(roomId, beforeTS, limit);
    console.time(`[MatrixTimelineService] mapRepoEventsToMessages(${roomId})`);
    const messages = await this.mapRepoEventsToMessages(events);
    // Ensure chronological order (oldest first) for consumers
    messages.sort((a, b) => a.timestamp - b.timestamp);
    console.timeEnd(`[MatrixTimelineService] mapRepoEventsToMessages(${roomId})`);
    return { messages, nextBatch: firstTS };
  }

  /* ---------------- Mapping helpers ---------------- */

  async mapRepoEventsToMessages(events: RepoEvent[]): Promise<MatrixMessage[]> {
    const currentUserId = this.data.getCurrentUserId() ?? '';
    const msgs: MatrixMessage[] = [];
    const resolvers: Array<Promise<void>> = [];
    for (const re of events.filter(
      (re) => re.type === EventType.RoomMessage || re.type === 'm.room.encrypted'
    )) {
      // MatrixDataLayer ensures re.content is the effective content:
      // - clear for decrypted
      // - m.bad.encrypted body for failures
      const c = re.content as any;
      const body = typeof c?.body === 'string' ? (c.body as string) : undefined;
      const isSelf = re.sender === currentUserId;
      // Prefer cached display name from store, then SDK membership, else MXID
      let senderDisplayName = (await this.data.getUserDisplayName(re.sender)) || re.sender;
      if (!senderDisplayName) senderDisplayName = re.sender;
      const msgtype = c?.msgtype;

      const msg: MatrixMessage = {
        id: re.eventId,
        sender: re.sender || 'unknown sender',
        senderDisplayName,
        senderAvatarUrl: undefined,
        body: body ?? '',
        timestamp: re.originServerTs || 0,
        isSelf,
        msgtype,
      };

      // Resolve sender avatar via AvatarService and assign onto msg
      const pAvatar = this.avatars
        .resolveUserAvatar(re.sender, { w: 32, h: 32, method: 'crop' })
        .then((url) => {
          if (url) {
            msg.senderAvatarUrl = url;
            this.bumpMediaVersion();
          }
        })
        .catch((err) => {
          console.warn('[MatrixTimelineService] resolveUserAvatar failed', err);
        });
      resolvers.push(pAvatar);

      console.time(`[MatrixTimelineService] resolveMedia(${re.eventId})`);
      if (msgtype === matrixSdk.MsgType.Image) {
        const content = c as ImageContent;
        msg.mxcUrl = content.file?.url ?? content.url;
        const p = this.data
          .resolveImage(content)
          .then((blobUrl) => {
            if (blobUrl) {
              msg.imageUrl = blobUrl;
              this.bumpMediaVersion();
            }
          })
          .catch((err) => {
            console.warn('[MatrixTimelineService] resolveImage failed', err);
          })
          .finally(() => {
            console.timeEnd(`[MatrixTimelineService] resolveMedia(${re.eventId})`);
          });
        resolvers.push(p);
      } else if (msgtype === matrixSdk.MsgType.File) {
        const content = c;
        msg.mxcUrl = content.file?.url ?? content.url;
        msg.fileName = content.filename || body || 'file';
        const p = this.data
          .resolveFile(content)
          .then((blobUrl) => {
            if (blobUrl) {
              msg.fileUrl = blobUrl;
              this.bumpMediaVersion();
            }
          })
          .catch((err) => {
            console.warn('[MatrixTimelineService] resolveFile failed', err);
          })
          .finally(() => {
            console.timeEnd(`[MatrixTimelineService] resolveMedia(${re.eventId})`);
          });
        resolvers.push(p);
      } else {
        console.timeEnd(`[MatrixTimelineService] resolveMedia(${re.eventId})`);
      }

      msgs.push(msg);
    }

    // Kick off avatar and image resolution without blocking
    if (resolvers.length) void Promise.allSettled(resolvers);
    return msgs;
  }

  // removed batch read count computation; read status is derived at render time

  // Media cache management
  clearMediaCache(): void {}

  /** Create a human preview from RepoEvent content (clear or failure content). */
  private repoEventToPreview(re: RepoEvent): { description: string } {
    const c = re.content as any;

    // Images: show filename or generic label
    if (c?.msgtype === matrixSdk.MsgType.Image) {
      const body = c.body;
      return { description: `Image: ${typeof body === 'string' ? body : 'Image'}` };
    }
    // Files: show filename or generic label
    if (c?.msgtype === matrixSdk.MsgType.File) {
      const name = c.filename || c.body;
      return { description: `File: ${typeof name === 'string' ? name : 'file'}` };
    }
    // Decryption failure body (from sdk: msgtype m.bad.encrypted)
    if (c?.msgtype === 'm.bad.encrypted' && typeof c?.body === 'string') {
      return { description: c.body };
    }
    // Plain text
    if (typeof c?.body === 'string') return { description: c.body };

    const relates = c?.['m.relates_to'];
    if (relates?.rel_type === 'm.annotation') {
      const key = typeof c.key === 'string' ? (c.key as string) : undefined;
      if (key) {
        return { description: `${re.sender} reacted with ${key}` };
      }
    }
    if (relates?.rel_type === 'm.reference') {
      return { description: 'Replied to a message' };
    }
    // Final fallback: if still encrypted, prefer a short hint
    if (re.type === 'm.room.encrypted') return { description: 'Unable to decrypt.' };
    return { description: 'Unsupported message' };
  }

  // removed avatar helpers: now handled by AvatarService
}
