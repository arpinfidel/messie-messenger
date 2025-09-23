import * as matrixSdk from 'matrix-js-sdk';
import { EventType } from 'matrix-js-sdk';
import { writable, type Writable, get } from 'svelte/store';

import type { TimelineItem } from '@/models/shared/TimelineItem';
import type { RepoEvent } from './core/TimelineRepository';
import { MatrixDataLayer } from './core/MatrixDataLayer';
import type { ImageContent } from 'matrix-js-sdk/lib/@types/media';
import { AvatarService } from './core/AvatarService';
import type { INotificationService } from '@/notifications/NotificationService';
import { matrixSettings } from './MatrixSettings';
import type { DbRoom } from './core/idb/constants';
import { MATRIX_BRIDGE_USER_ID_TO_SOURCE } from '@/config/timelineSources';

export interface MatrixMessageVersion {
  body: string;
  timestamp: number;
  eventId: string;
  sender: string;
  senderDisplayName: string;
}

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
  isEdited?: boolean;
  lastEditedTimestamp?: number;
  lastEditEventId?: string;
  editHistory?: MatrixMessageVersion[];
}

export class MatrixTimelineService {
  private _timelineItems: Writable<TimelineItem[]> = writable([]);
  private nextTimeline: Map<string, TimelineItem> = new Map();
  private flushTimeout: ReturnType<typeof setTimeout> | null = null;
  private readonly maxRooms = 30; // limit room list to most recent N
  // Invalidate counter to notify UI when async media resolves
  private mediaVersion: Writable<number> = writable(0);
  private notifications?: INotificationService;
  private lastNotifyByRoom = new Map<string, number>();
  private messageCache = new Map<string, MatrixMessage>();
  private readonly bridgeUserIdToSource: ReadonlyMap<string, string> =
    MATRIX_BRIDGE_USER_ID_TO_SOURCE;

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

  getTimelineItemsStore(): Writable<TimelineItem[]> {
    return this._timelineItems;
  }

  getMediaVersionStore(): Writable<number> {
    return this.mediaVersion;
  }

  private bumpMediaVersion() {
    this.mediaVersion.update((n) => n + 1);
  }

  async initTimeline(opts: { offlineOnly?: boolean } = {}): Promise<void> {
    const rooms = await this.data.getRooms();
    // Sort rooms by latest activity and keep only top N
    const sortedRooms = rooms
      .slice()
      .sort((a, b) => (b.latestTimestamp ?? 0) - (a.latestTimestamp ?? 0));
    const activeRooms = sortedRooms.slice(0, this.maxRooms);
    const inactiveRooms = sortedRooms.slice(this.maxRooms);

    // Process active rooms and wait for them to be added to the timeline
    await this._processRooms(activeRooms, opts);

    // Process inactive rooms in the background
    void this._processRooms(inactiveRooms, opts);
  }

  private async _processRooms(rooms: DbRoom[], opts: { offlineOnly?: boolean }): Promise<void> {
    if (!rooms.length) {
      return;
    }

    const currentItemsByID = this.nextTimeline;

    // 1. Create initial timeline items in parallel
    const items = await Promise.all(
      rooms.map(async (room) => {
        let lastEvent = room.lastEvent ?? undefined;
        if (!lastEvent && !opts?.offlineOnly) {
          const cached = await this.data.getLatestCachedMessages(room.id, null, 1);
          lastEvent = cached.events[0];
        }
        let description = 'No recent messages';
        let timestamp = room.latestTimestamp || 0;
        if (lastEvent) {
          description = this.repoEventToPreview(lastEvent);
          timestamp = lastEvent.originServerTs || timestamp || 0;
        }
        // get previous avatar if available
        const existingItem = currentItemsByID.get(room.id);
        const avatarUrl: string | undefined = existingItem?.avatarUrl;
        const mxRoom = this.client?.getRoom(room.id) ?? null;
        const computedSource = this.computeRoomSource(mxRoom);
        const source =
          computedSource === 'matrix' && existingItem?.source && existingItem.source !== 'matrix'
            ? existingItem.source
            : computedSource;

        const item: TimelineItem = {
          id: room.id,
          type: 'matrix',
          title: room.name || room.id,
          description,
          avatarUrl,
          timestamp,
          unreadCount: room.unreadCount || 0,
          source,
        };
        return item;
      })
    );

    for (const newItem of items) {
      this.bufferTimelineUpdate(newItem);
    }
    this.scheduleFlush(); // Flush once after initial items

    // 2. Resolve avatars in background
    const maxConcurrent = 6;
    let i = 0;
    const work = async () => {
      try {
        while (i < rooms.length) {
          const idx = i++;
          const room = rooms[idx];
          const url = await this.avatars.resolveRoomAvatar(room.id, room.avatarMxcUrl, {
            w: 64,
            h: 64,
            method: 'crop' as const,
          });

          const existingItem = this.nextTimeline.get(room.id);
          if (!existingItem) {
            continue;
          }

          const updated: TimelineItem = {
            ...existingItem,
            avatarUrl: url || existingItem.avatarUrl,
          };

          this.bufferTimelineUpdate(updated);
          this.scheduleFlush();
        }
      } catch (e) {
        console.warn('Error resolving room avatar:', e);
      }
    };

    for (let k = 0; k < Math.min(maxConcurrent, rooms.length); k++) {
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
      const description = ev ? this.repoEventToPreview(ev) : '';
      const body = typeof ev?.content?.body === 'string' ? (ev!.content.body as string) : undefined;

      let avatarUrl: string | undefined;
      const roomMxc = room.getMxcAvatarUrl();
      avatarUrl = await this.avatars.resolveRoomAvatar(room.roomId, roomMxc || undefined, {
        w: 64,
        h: 64,
        method: 'crop' as const,
      });

      const previousItem =
        this.nextTimeline.get(id) ||
        (get(this._timelineItems).find((it) => it.id === id) as TimelineItem | undefined);
      const computedSource = this.computeRoomSource(room);
      const source =
        computedSource === 'matrix' && previousItem?.source && previousItem.source !== 'matrix'
          ? previousItem.source
          : computedSource;
      const updated: TimelineItem = {
        id,
        type: 'matrix',
        title,
        description,
        // Keep previous avatar if resolve failed
        avatarUrl: avatarUrl || previousItem?.avatarUrl,
        timestamp,
        unreadCount,
        source,
      };

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
        const isVisible = document && document.visibilityState === 'visible';
        const hasFocus = document && typeof document.hasFocus && document.hasFocus();
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
              const senderName = (await this.data.getUserDisplayName(ev.sender)) || ev.sender;
              void this.notifications.notify({
                title: `${senderName} in ${title}`,
                body: body ?? description,
                icon: avatarUrl,
                onClick: () => {
                  window.focus();
                  window.dispatchEvent(new CustomEvent('messie-open-room', { detail: id }));
                },
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

  bufferTimelineUpdate(item: TimelineItem) {
    const existing = this.nextTimeline.get(item.id);
    if (!existing || (existing.timestamp ?? 0) <= item.timestamp) {
      this.nextTimeline.set(item.id, item);
    }
  }

  setRoomUnread(roomId: string, unreadCount: number) {
    const existing = this.nextTimeline.get(roomId);
    if (!existing) return;
    const updated: TimelineItem = {
      id: existing.id,
      type: existing.type,
      title: existing.title,
      description: existing.description,
      avatarUrl: existing.avatarUrl,
      timestamp: existing.timestamp,
      rawData: existing.rawData,
      sender: existing.sender,
      unreadCount,
      source: existing.source,
    };
    this.bufferTimelineUpdate(updated);
    this.scheduleFlush();
  }

  private computeRoomSource(room: matrixSdk.Room | null): string {
    if (!room) {
      return 'matrix';
    }
    const bridgeSource = this.resolveBridgeSource(room);
    return bridgeSource ?? 'matrix';
  }

  private resolveBridgeSource(room: matrixSdk.Room): string | null {
    for (const [userId, sourceId] of this.bridgeUserIdToSource) {
      const member = room.getMember(userId);
      if (member?.membership === 'join') {
        return sourceId;
      }
    }
    return null;
  }

  async scheduleFlush() {
    if (this.flushTimeout) return;
    this.flushTimeout = setTimeout(() => {
      const sorted = Array.from(this.nextTimeline.values()).sort(
        (a, b) => (b.timestamp ?? 0) - (a.timestamp ?? 0)
      );
      this._timelineItems.set(sorted);
      this.flushTimeout = null;
    }, 100);
  }

  /* ---------------- Room messages API (delegates to repo) ---------------- */

  /** First page: from live timeline when fromToken is null, otherwise older page. */
  async getRoomMessages(
    roomId: string,
    beforeIndex: number | null,
    limit = 20
  ): Promise<{ messages: MatrixMessage[]; nextBatch: number | null }> {
    const { events, firstIndex } = await this.data.getRoomEvents(roomId, beforeIndex, limit);
    console.time(`[MatrixTimelineService] mapRepoEventsToMessages(${roomId})`);
    const messages = await this.mapRepoEventsToMessages(events);
    // Ensure chronological order (oldest first) for consumers
    messages.sort((a, b) => a.timestamp - b.timestamp);
    console.timeEnd(`[MatrixTimelineService] mapRepoEventsToMessages(${roomId})`);
    return { messages, nextBatch: firstIndex };
  }

  /* ---------------- Mapping helpers ---------------- */

  async mapRepoEventsToMessages(events: RepoEvent[]): Promise<MatrixMessage[]> {
    const currentUserId = this.data.getCurrentUserId() ?? '';
    const updates = new Map<string, MatrixMessage>();
    const resolvers: Array<Promise<void>> = [];
    const pendingEdits = new Map<string, RepoEvent[]>();

    const applyEdit = (target: MatrixMessage | undefined, editEvent: RepoEvent) => {
      if (!target) return;
      if (target.lastEditEventId === editEvent.eventId) {
        return;
      }
      const editContent = editEvent.content as any;
      const newContent = editContent?.['m.new_content'];
      const fallbackBody =
        typeof editContent?.body === 'string' ? (editContent.body as string) : target.body;
      const newBody =
        typeof newContent?.body === 'string'
          ? (newContent.body as string)
          : fallbackBody;

      if (!target.editHistory) {
        target.editHistory = [];
      }

      const previousEventId = target.lastEditEventId ?? target.id;
      const alreadyRecorded = target.editHistory.some((entry) => entry.eventId === previousEventId);
      if (!alreadyRecorded) {
        target.editHistory.push({
          body: target.body,
          timestamp: target.lastEditedTimestamp ?? target.timestamp,
          eventId: previousEventId,
          sender: target.sender,
          senderDisplayName: target.senderDisplayName,
        });
      }

      if (typeof newBody === 'string') {
        target.body = newBody;
      }

      const newMsgtype =
        typeof newContent?.msgtype === 'string' ? (newContent.msgtype as string) : undefined;
      if (newMsgtype) {
        target.msgtype = newMsgtype;
      }

      target.isEdited = true;
      target.lastEditedTimestamp =
        editEvent.originServerTs || target.lastEditedTimestamp || target.timestamp;
      target.lastEditEventId = editEvent.eventId;
    };

    const flushPendingEdits = (msg: MatrixMessage) => {
      const pending = pendingEdits.get(msg.id);
      if (!pending) return;
      for (const editEv of pending) {
        applyEdit(msg, editEv);
      }
      pendingEdits.delete(msg.id);
    };

    for (const re of events.filter(
      (evt) => evt.type === EventType.RoomMessage || evt.type === 'm.room.encrypted'
    )) {
      const c = re.content as any;
      const relates = c?.['m.relates_to'];

      if (relates?.rel_type === 'm.replace' && typeof relates?.event_id === 'string') {
        const targetId = relates.event_id as string;
        const target = this.messageCache.get(targetId);
        if (target) {
          applyEdit(target, re);
          updates.set(targetId, target);
        } else {
          const queued = pendingEdits.get(targetId) ?? [];
          queued.push(re);
          pendingEdits.set(targetId, queued);
        }
        continue;
      }

      const body = typeof c?.body === 'string' ? (c.body as string) : undefined;
      const isSelf = re.sender === currentUserId;
      // Prefer cached display name from store, then SDK membership, else MXID
      let senderDisplayName =
        (await this.data.getUserDisplayName(re.sender)) || re.sender;
      if (!senderDisplayName) senderDisplayName = re.sender;
      const msgtype = c?.msgtype;

      let msg = this.messageCache.get(re.eventId);
      const isNewMessage = !msg;
      if (!msg) {
        msg = {
          id: re.eventId,
          sender: re.sender || 'unknown sender',
          senderDisplayName,
          senderAvatarUrl: undefined,
          body: body ?? '',
          timestamp: re.originServerTs || 0,
          isSelf,
          msgtype,
          imageUrl: undefined,
          fileUrl: undefined,
          fileName: undefined,
          mxcUrl: undefined,
          isEdited: false,
          lastEditedTimestamp: undefined,
          lastEditEventId: undefined,
          editHistory: [],
        };
        this.messageCache.set(re.eventId, msg);
      } else {
        msg.sender = re.sender || msg.sender;
        msg.senderDisplayName = senderDisplayName || msg.senderDisplayName;
        msg.timestamp = re.originServerTs || msg.timestamp;
        msg.isSelf = isSelf;
        if (typeof body === 'string') {
          msg.body = body;
        }
        if (msgtype) {
          msg.msgtype = msgtype;
        }
        if (!msg.editHistory) {
          msg.editHistory = [];
        }
      }

      if (!msg.senderAvatarUrl) {
        const pAvatar = this.avatars
          .resolveUserAvatar(re.sender, { w: 32, h: 32, method: 'crop' as const })
          .then((url) => {
            if (url) {
              msg!.senderAvatarUrl = url;
              this.bumpMediaVersion();
            }
          })
          .catch((err) => {
            console.warn('[MatrixTimelineService] resolveUserAvatar failed', err);
          });
        resolvers.push(pAvatar);
      }

      console.time(`[MatrixTimelineService] resolveMedia(${re.eventId})`);
      if (msgtype === matrixSdk.MsgType.Image) {
        const content = c as ImageContent;
        const newMxc = content.file?.url ?? content.url;
        const shouldResolve = isNewMessage || msg.mxcUrl !== newMxc || !msg.imageUrl;
        msg.mxcUrl = newMxc;
        msg.fileName = content.filename || body || 'file';
        msg.fileUrl = undefined;
        if (shouldResolve) {
          const p = this.data
            .resolveImage(content)
            .then((blobUrl) => {
              if (blobUrl) {
                msg!.imageUrl = blobUrl;
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
        } else {
          console.timeEnd(`[MatrixTimelineService] resolveMedia(${re.eventId})`);
        }
      } else if (msgtype === matrixSdk.MsgType.File) {
        const content = c;
        const newMxc = content.file?.url ?? content.url;
        const shouldResolve = isNewMessage || msg.mxcUrl !== newMxc || !msg.fileUrl;
        msg.mxcUrl = newMxc;
        msg.fileName = content.filename || body || 'file';
        msg.imageUrl = undefined;
        if (shouldResolve) {
          const p = this.data
            .resolveFile(content)
            .then((blobUrl) => {
              if (blobUrl) {
                msg!.fileUrl = blobUrl;
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
      } else {
        if (isNewMessage) {
          msg.imageUrl = undefined;
          msg.fileUrl = undefined;
          msg.fileName = undefined;
        }
        msg.mxcUrl = undefined;
        console.timeEnd(`[MatrixTimelineService] resolveMedia(${re.eventId})`);
      }

      flushPendingEdits(msg);
      updates.set(msg.id, msg);
    }

    // Apply any queued edits for messages already cached but not part of this batch
    for (const [targetId, edits] of Array.from(pendingEdits.entries())) {
      const target = this.messageCache.get(targetId);
      if (!target) continue;
      for (const editEv of edits) {
        applyEdit(target, editEv);
      }
      updates.set(targetId, target);
      pendingEdits.delete(targetId);
    }

    // Kick off avatar and image resolution without blocking
    if (resolvers.length) void Promise.allSettled(resolvers);
    return Array.from(updates.values());
  }

  // removed batch read count computation; read status is derived at render time

  // Media cache management
  clearMediaCache(): void {}

  /** Create a human preview from RepoEvent content (clear or failure content). */
  private repoEventToPreview(re: RepoEvent): string {
    const c = re.content as any;

    // Images: show filename or generic label
    if (c?.msgtype === matrixSdk.MsgType.Image) {
      const body = c.body;
      return `Image: ${typeof body === 'string' ? body : 'Image'}`;
    }
    // Files: show filename or generic label
    if (c?.msgtype === matrixSdk.MsgType.File) {
      const name = c.filename || c.body;
      return `File: ${typeof name === 'string' ? name : 'file'}`;
    }
    // Decryption failure body (from sdk: msgtype m.bad.encrypted)
    if (c?.msgtype === 'm.bad.encrypted' && typeof c?.body === 'string') {
      return c.body;
    }
    const relates = c?.['m.relates_to'];
    if (relates?.rel_type === 'm.replace') {
      const newBody =
        typeof c?.['m.new_content']?.body === 'string'
          ? (c['m.new_content'].body as string)
          : undefined;
      if (newBody) {
        return newBody;
      }
    }

    // Plain text
    if (typeof c?.body === 'string') return c.body;

    if (relates?.rel_type === 'm.annotation') {
      const key = typeof c.key === 'string' ? (c.key as string) : undefined;
      if (key) {
        return `${re.sender} reacted with ${key}`;
      }
    }
    if (relates?.rel_type === 'm.reference') {
      return 'Replied to a message';
    }
    // Final fallback: if still encrypted, prefer a short hint
    if (re.type === 'm.room.encrypted') return 'Unable to decrypt.';
    return 'Unsupported message';
  }
}
