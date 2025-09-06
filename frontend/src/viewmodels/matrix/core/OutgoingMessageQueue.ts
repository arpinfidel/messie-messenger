import type * as matrixSdk from 'matrix-js-sdk';

export interface OutgoingItem {
  roomId: string;
  eventType: string;
  content: any;
}

export class OutgoingMessageQueue {
  private queue: OutgoingItem[] = [];
  private processing = false;

  constructor(private getClient: () => matrixSdk.MatrixClient | null) {}

  enqueue(roomId: string, eventType: string, content: any) {
    this.queue.push({ roomId, eventType, content });
  }

  get size() {
    return this.queue.length;
  }

  async process() {
    const client = this.getClient();
    if (this.processing || !client || !client.isLoggedIn()) return;

    this.processing = true;
    try {
      while (this.queue.length) {
        const msg = this.queue[0];
        try {
          await client.sendEvent(msg.roomId, msg.eventType, msg.content);
          this.queue.shift();
        } catch (e) {
          // keep head in queue; bail out to retry later
          break;
        }
      }
    } finally {
      this.processing = false;
    }
  }
}
