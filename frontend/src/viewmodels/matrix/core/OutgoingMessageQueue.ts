import type * as matrixSdk from 'matrix-js-sdk';

export interface OutgoingItem {
  roomId: string;
  eventType: string;
  content: any;
  attempts?: number;
}

export class OutgoingMessageQueue {
  private queue: OutgoingItem[] = [];
  private processing = false;

  constructor(private getClient: () => matrixSdk.MatrixClient | null) {}

  enqueue(roomId: string, eventType: string, content: any) {
    this.queue.push({ roomId, eventType, content });
    try {
      // Fire-and-forget; caller usually also calls process()
      console.debug('[OutgoingQueue] enqueued', {
        roomId,
        eventType,
        size: this.queue.length,
      });
    } catch {}
  }

  get size() {
    return this.queue.length;
  }

  async process() {
    const client = this.getClient();
    if (this.processing) return;
    if (!client || !client.isLoggedIn()) {
      console.warn('[OutgoingQueue] cannot process: client not ready or not logged in', {
        size: this.queue.length,
      });
      return;
    }

    this.processing = true;
    try {
      console.debug('[OutgoingQueue] processing started', { size: this.queue.length });
      while (this.queue.length) {
        const msg = this.queue[0];
        try {
          const res: any = await client.sendEvent(
            msg.roomId,
            msg.eventType as any,
            msg.content
          );
          console.debug('[OutgoingQueue] send succeeded', {
            roomId: msg.roomId,
            eventType: msg.eventType,
            eventId: res?.event_id,
          });
          this.queue.shift();
        } catch (e) {
          const anyErr = e as any;
          const code = anyErr?.errcode || anyErr?.data?.errcode;
          const status = anyErr?.httpStatus || anyErr?.status || anyErr?.data?.status;
          const message = anyErr?.message || anyErr?.data?.error || String(anyErr);
          console.warn('[OutgoingQueue] send failed', {
            roomId: msg.roomId,
            eventType: msg.eventType,
            code,
            status,
            message,
          });
          // keep head in queue; schedule a retry with basic backoff
          const attempts = (msg.attempts || 0) + 1;
          msg.attempts = attempts;

          // Try to respect rate limit if provided
          let delay = 0;
          const retryAfter = anyErr?.retry_after_ms || anyErr?.data?.retry_after_ms;
          if (typeof retryAfter === 'number' && retryAfter > 0) {
            delay = retryAfter;
          } else {
            // Exponential backoff, cap at 30s
            delay = Math.min(30000, 1000 * Math.pow(2, attempts - 1));
          }
          console.warn('[OutgoingQueue] scheduling retry', {
            attempts,
            delayMs: delay,
            size: this.queue.length,
          });
          // Schedule retry and exit loop
          setTimeout(() => this.process().catch(() => {}), delay);
          break;
        }
      }
    } finally {
      this.processing = false;
      console.debug('[OutgoingQueue] processing ended', { size: this.queue.length });
    }
  }
}
