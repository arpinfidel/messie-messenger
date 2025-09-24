import * as matrixSdk from 'matrix-js-sdk';
import type { EncryptedFile } from 'matrix-js-sdk/lib/@types/media';
import type { ClientGetter } from './MatrixClientManager';
import { BrowserMediaService } from './MediaService';
import { OutgoingMessageQueue } from './OutgoingMessageQueue';
import type { MatrixReplyContext } from '../types';

export class MatrixMessagingService {
  private readonly queue: OutgoingMessageQueue;
  private readonly mediaService: BrowserMediaService;

  constructor(private readonly getClient: ClientGetter, mediaService?: BrowserMediaService) {
    this.queue = new OutgoingMessageQueue(this.getClient);
    this.mediaService = mediaService ?? new BrowserMediaService();
  }

  async pickMedia(): Promise<File | undefined> {
    return this.mediaService.pickMedia();
  }

  async pickFile(): Promise<File | undefined> {
    return this.mediaService.pickFile();
  }

  async sendMedia(roomId: string, replyTo?: MatrixReplyContext): Promise<void> {
    const file = await this.mediaService.pickMedia();
    if (!file) return;
    const caption =
      typeof window !== 'undefined'
        ? window.prompt('Add a caption (optional):') || undefined
        : undefined;
    await this.sendAttachment(roomId, file, caption, replyTo);
  }

  async sendFile(roomId: string, replyTo?: MatrixReplyContext): Promise<void> {
    const file = await this.mediaService.pickFile();
    if (!file) return;
    const caption =
      typeof window !== 'undefined'
        ? window.prompt('Add a caption (optional):') || undefined
        : undefined;
    await this.sendAttachment(roomId, file, caption, replyTo);
  }

  async sendAttachment(
    roomId: string,
    file: File,
    caption?: string,
    replyTo?: MatrixReplyContext
  ): Promise<void> {
    const client = this.resolveClient();
    if (!client) {
      console.error('Cannot send media: Matrix client not initialized.');
      return;
    }
    const isEncryptedRoom = client.isRoomEncrypted(roomId);
    const msgtype = file.type.startsWith('image/')
      ? matrixSdk.MsgType.Image
      : file.type.startsWith('video/')
        ? matrixSdk.MsgType.Video
        : matrixSdk.MsgType.File;

    const content: any = {
      body: caption ?? '',
      filename: file.name || 'file',
      msgtype,
      info: { mimetype: file.type || 'application/octet-stream', size: file.size },
    };

    const prepared = this.buildReplyEnvelope(caption ?? '', replyTo);
    content.body = prepared.body;
    if (prepared.relatesTo) {
      content['m.relates_to'] = prepared.relatesTo;
    }

    if (msgtype === matrixSdk.MsgType.Image) {
      const dims = await this.getImageSize(file).catch(() => undefined);
      if (dims) {
        content.info.w = dims.width;
        content.info.h = dims.height;
      }
    }

    try {
      if (isEncryptedRoom) {
        const enc = await this.encryptAttachment(file);
        const res = await client.uploadContent(new Blob([enc.data]), {
          type: 'application/octet-stream',
        });
        content.file = { ...enc.file, url: res.content_uri } as EncryptedFile;
      } else {
        const res = await client.uploadContent(file, { type: file.type });
        content.url = res.content_uri;
      }

      this.queue.enqueue(roomId, 'm.room.message', content);
      this.queue.process();
    } catch (e) {
      console.error('Failed to send media message', e);
    }
  }

  async sendMessage(
    roomId: string,
    messageContent: string,
    replyTo?: MatrixReplyContext
  ): Promise<void> {
    if (!this.resolveClient()) {
      console.error('Cannot send message: Matrix client not initialized.');
      return;
    }
    const prepared = this.buildReplyEnvelope(messageContent, replyTo);
    const content: any = { body: prepared.body, msgtype: 'm.text' };
    if (prepared.relatesTo) {
      content['m.relates_to'] = prepared.relatesTo;
    }
    this.queue.enqueue(roomId, 'm.room.message', content);
    this.queue.process();
  }

  async editMessage(
    roomId: string,
    targetEventId: string,
    messageContent: string,
    replyToEventId?: string,
    msgtype?: string
  ): Promise<void> {
    if (!this.resolveClient()) {
      console.error('Cannot edit message: Matrix client not initialized.');
      return;
    }

    const trimmed = messageContent.trim();
    if (!trimmed.length) {
      console.warn('[MatrixMessagingService] Ignoring empty edit payload');
      return;
    }

    const finalMsgtype = msgtype ?? 'm.text';
    const newContent: any = {
      body: trimmed,
      msgtype: finalMsgtype,
    };

    if (replyToEventId) {
      newContent['m.relates_to'] = { 'm.in_reply_to': { event_id: replyToEventId } };
    }

    const content: any = {
      msgtype: finalMsgtype,
      body: `* ${trimmed}`,
      'm.new_content': newContent,
      'm.relates_to': {
        rel_type: 'm.replace',
        event_id: targetEventId,
      },
    };

    if (replyToEventId) {
      content['m.relates_to']['m.in_reply_to'] = { event_id: replyToEventId };
    }

    this.queue.enqueue(roomId, 'm.room.message', content);
    this.queue.process();
  }

  private buildReplyEnvelope(
    messageContent: string,
    replyTo?: MatrixReplyContext
  ): {
    body: string;
    relatesTo?: { 'm.in_reply_to': { event_id: string } };
  } {
    if (!replyTo?.eventId) {
      return { body: messageContent };
    }

    const senderLabel =
      replyTo.senderDisplayName?.trim() ||
      replyTo.sender?.trim() ||
      replyTo.fallbackSender?.trim() ||
      'Unknown';

    const snippetCandidate =
      replyTo.body?.trim() ||
      replyTo.fallbackBody?.trim() ||
      this.describeMsgtype(replyTo.msgtype);

    const normalizedSnippet = snippetCandidate
      ? snippetCandidate.replace(/\s+/g, ' ').trim()
      : '';
    const truncatedSnippet =
      normalizedSnippet.length > 200
        ? `${normalizedSnippet.slice(0, 197)}…`
        : normalizedSnippet;
    const fallbackLine = truncatedSnippet
      ? `> <${senderLabel}> ${truncatedSnippet}`
      : `> <${senderLabel}>`;

    const finalBody = messageContent.length
      ? `${fallbackLine}\n\n${messageContent}`
      : `${fallbackLine}\n\n`;

    return {
      body: finalBody,
      relatesTo: { 'm.in_reply_to': { event_id: replyTo.eventId } },
    };
  }

  private describeMsgtype(msgtype?: string): string {
    switch (msgtype) {
      case matrixSdk.MsgType.Image:
        return 'Image';
      case matrixSdk.MsgType.Video:
        return 'Video';
      case matrixSdk.MsgType.File:
        return 'File';
      case matrixSdk.MsgType.Audio:
        return 'Audio';
      default:
        return msgtype?.trim() || 'message';
    }
  }

  private resolveClient(): matrixSdk.MatrixClient | null {
    return this.getClient();
  }

  private async getImageSize(file: File): Promise<{ width: number; height: number }> {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        resolve({ width: img.width, height: img.height });
        URL.revokeObjectURL(url);
      };
      img.onerror = (err) => {
        URL.revokeObjectURL(url);
        reject(err);
      };
      img.src = url;
    });
  }

  private async encryptAttachment(
    file: File
  ): Promise<{ data: ArrayBuffer; file: Omit<EncryptedFile, 'url'> }> {
    const data = await file.arrayBuffer();
    const iv = crypto.getRandomValues(new Uint8Array(16));
    const keyBytes = crypto.getRandomValues(new Uint8Array(32));
    const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-CTR', true, ['encrypt', 'decrypt']);
    const cipher = await crypto.subtle.encrypt({ name: 'AES-CTR', counter: iv, length: 64 }, key, data);
    const hashBuf = await crypto.subtle.digest('SHA-256', cipher);
    const keyJwk = (await crypto.subtle.exportKey('jwk', key)) as EncryptedFile['key'];
    keyJwk.alg = 'A256CTR';
    keyJwk.key_ops = ['encrypt', 'decrypt'];
    keyJwk.ext = true;

    const toBase64Unpadded = (buf: ArrayBuffer | Uint8Array) => {
      const bytes = buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf;
      let binary = '';
      for (const b of bytes) binary += String.fromCharCode(b);
      return btoa(binary).replace(/=+$/, '');
    };

    return {
      data: cipher,
      file: {
        v: 'v2',
        key: keyJwk,
        iv: toBase64Unpadded(iv),
        hashes: { sha256: toBase64Unpadded(hashBuf) },
      },
    };
  }
}
