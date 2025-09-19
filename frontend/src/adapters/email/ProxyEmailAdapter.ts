import { DefaultApi } from '@/api/generated/apis/DefaultApi';
import type { EmailListRequest } from '@/api/generated/models/EmailListRequest';
import type { EmailMessagesResponse } from '@/api/generated/models/EmailMessagesResponse';
import type { EmailRichHeader } from '@/api/generated/models/EmailRichHeader';
import { Configuration, ResponseError } from '@/api/generated/runtime';
import type { EmailCredentials } from '@/viewmodels/email/EmailCredentialsStore';
import type {
  AdapterRichHeader,
  EmailAdapter,
  EmailListResult,
  ImportantFetchOptions,
} from './IEmailAdapter';

function normalizeUnknown(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === 'string' && error.trim()) return error;
  try {
    return JSON.stringify(error);
  } catch {
    return 'Unknown error';
  }
}

export class ProxyEmailAdapter implements EmailAdapter {
  private readonly api: DefaultApi;

  constructor(baseUrl = '/api/v1/email') {
    const trimmed = baseUrl.replace(/\/+$/, '');
    const basePath = trimmed.endsWith('/email')
      ? trimmed.slice(0, trimmed.length - '/email'.length)
      : trimmed || '/api/v1';
    this.api = new DefaultApi(new Configuration({ basePath }));
  }

  fetchInbox(_credentials: EmailCredentials): Promise<EmailListResult> {
    throw new Error('Method not implemented.');
  }

  async testCredentials(credentials: EmailCredentials): Promise<EmailListResult> {
    return await this.fetchListResult(async () =>
      await this.api.emailLoginTest({ emailLoginRequest: this.toEmailLoginRequest(credentials) })
    );
  }

  async fetchMailbox(
    credentials: EmailCredentials,
    options?: ImportantFetchOptions
  ): Promise<EmailListResult> {
    const request: EmailListRequest = {
      ...this.toEmailLoginRequest(credentials),
      ...(options?.mailbox ? { mailbox: options.mailbox } : {}),
      ...(options?.searchFlags ? { searchFlags: options.searchFlags } : {}),
    };

    return await this.fetchListResult(async () =>
      await this.api.emailList({ emailListRequest: request })
    );
  }

  async fetchRecentHeaders(credentials: EmailCredentials): Promise<AdapterRichHeader[]> {
    try {
      const response = await this.api.emailHeaders({
        emailLoginRequest: this.toEmailLoginRequest(credentials),
      });
      const messages = Array.isArray(response?.messages) ? response.messages : [];
      return messages
        .map((raw) => this.mapToRichHeader(raw))
        .filter((header): header is AdapterRichHeader => Boolean(header?.messageId));
    } catch (error) {
      throw new Error(await this.extractError(error));
    }
  }

  private toEmailLoginRequest(credentials: EmailCredentials) {
    return {
      host: credentials.host,
      port: credentials.port,
      email: credentials.email,
      appPassword: credentials.appPassword,
    };
  }

  private async fetchListResult(
    executor: () => Promise<EmailMessagesResponse>
  ): Promise<EmailListResult> {
    try {
      const payload = await executor();
      const messages = Array.isArray(payload.messages) ? payload.messages : [];
      const unreadCount = typeof payload.unreadCount === 'number' ? payload.unreadCount : 0;
      return { messages, unreadCount };
    } catch (error) {
      throw new Error(await this.extractError(error));
    }
  }

  private async extractError(error: unknown): Promise<string> {
    if (error instanceof ResponseError) {
      try {
        const text = await error.response.text();
        if (!text) {
          return `Request failed with status ${error.response.status}`;
        }
        try {
          const parsed = JSON.parse(text);
          if (typeof parsed === 'string' && parsed.trim()) return parsed;
          if (parsed?.message && typeof parsed.message === 'string') return parsed.message;
          return text;
        } catch {
          return text;
        }
      } catch (inner) {
        return `Request failed with status ${error.response.status}: ${normalizeUnknown(inner)}`;
      }
    }
    return normalizeUnknown(error);
  }

  private mapToRichHeader(raw: EmailRichHeader | null | undefined): AdapterRichHeader | null {
    if (!raw) return null;

    const messageId = typeof raw.messageId === 'string' ? raw.messageId.trim() : '';
    if (!messageId) {
      return null;
    }

    const date = raw.date instanceof Date && !Number.isNaN(raw.date.getTime()) ? raw.date : undefined;
    const references = Array.isArray(raw.references)
      ? raw.references
          .map((ref) => (typeof ref === 'string' ? ref.trim() : ''))
          .filter((ref) => ref.length > 0)
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
