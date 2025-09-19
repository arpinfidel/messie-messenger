import type { EmailMessagesResponse } from '@/api/generated/models/EmailMessagesResponse';
import { EmailMessagesResponseFromJSON } from '@/api/generated/models/EmailMessagesResponse';
import type { EmailCredentials } from '@/viewmodels/email/EmailCredentialsStore';
import type {
  AdapterRichHeader,
  EmailAdapter,
  EmailListResult,
  ImportantFetchOptions,
} from './IEmailAdapter';

const JSON_HEADERS = { 'Content-Type': 'application/json' } as const;

function normalizeErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === 'string') return error;
  try {
    return JSON.stringify(error);
  } catch {
    return 'Unknown error';
  }
}

export class ProxyEmailAdapter implements EmailAdapter {
  private readonly baseUrl: string;

  constructor(baseUrl = '/api/v1/email') {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }
  fetchInbox(credentials: EmailCredentials): Promise<EmailListResult> {
    throw new Error('Method not implemented.');
  }

  async testCredentials(credentials: EmailCredentials): Promise<EmailListResult> {
    return this.postForList(`${this.baseUrl}/login-test`, credentials);
  }

  async fetchMailbox(
    credentials: EmailCredentials,
    options?: ImportantFetchOptions
  ): Promise<EmailListResult> {
    const payload = {
      ...credentials,
      ...(options?.mailbox ? { mailbox: options.mailbox } : {}),
      ...(options?.searchFlags ? { searchFlags: options.searchFlags } : {}),
    };
    return this.postForList(`${this.baseUrl}/list`, payload);
  }

  async fetchRecentHeaders(credentials: EmailCredentials): Promise<AdapterRichHeader[]> {
    const payload = await this.post(`${this.baseUrl}/headers`, credentials);
    const messages = Array.isArray(payload?.messages) ? payload.messages : [];
    return messages
      .map((raw: any) => this.mapToRichHeader(raw))
      .filter((header: AdapterRichHeader | null): header is AdapterRichHeader =>
        Boolean(header?.messageId)
      );
  }

  private async postForList(url: string, body: unknown): Promise<EmailListResult> {
    const payload = await this.post(url, body);
    const parsed: EmailMessagesResponse = EmailMessagesResponseFromJSON(payload);
    const messages = Array.isArray(parsed.messages) ? parsed.messages : [];
    const unreadCount = typeof parsed.unreadCount === 'number' ? parsed.unreadCount : 0;
    return {
      messages,
      unreadCount,
    };
  }

  private async post(url: string, body: unknown): Promise<any> {
    let response: Response;
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: JSON_HEADERS,
        body: JSON.stringify(body ?? {}),
      });
    } catch (err) {
      throw new Error(`Network failure: ${normalizeErrorMessage(err)}`);
    }

    if (!response.ok) {
      const message = await this.extractError(response);
      throw new Error(message);
    }

    try {
      return await response.json();
    } catch (err) {
      throw new Error(`Failed to parse JSON response: ${normalizeErrorMessage(err)}`);
    }
  }

  private async extractError(response: Response): Promise<string> {
    try {
      const text = await response.text();
      if (!text) {
        return `Request failed with status ${response.status}`;
      }
      try {
        const parsed = JSON.parse(text);
        if (typeof parsed === 'string') return parsed;
        if (parsed?.message && typeof parsed.message === 'string') return parsed.message;
        return text;
      } catch {
        return text;
      }
    } catch (err) {
      return `Request failed with status ${response.status}: ${normalizeErrorMessage(err)}`;
    }
  }

  private mapToRichHeader(raw: any): AdapterRichHeader | null {
    if (!raw) return null;

    const messageId = typeof raw.messageId === 'string' ? raw.messageId.trim() : '';
    const parsedDate = raw.date ? new Date(raw.date) : undefined;
    const date = parsedDate && !Number.isNaN(parsedDate.getTime()) ? parsedDate : undefined;
    const references = Array.isArray(raw.references)
      ? raw.references
          .map((ref: unknown) => (typeof ref === 'string' ? ref.trim() : ''))
          .filter((ref: string) => ref.length > 0)
      : [];

    return {
      from: typeof raw.from === 'string' ? raw.from : undefined,
      subject: typeof raw.subject === 'string' ? raw.subject : undefined,
      date,
      messageId,
      inReplyTo: typeof raw.inReplyTo === 'string' ? raw.inReplyTo.trim() || undefined : undefined,
      references,
    };
  }
}
