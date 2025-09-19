import { get, writable, type Readable } from 'svelte/store';
import type { Unsubscriber } from 'svelte/store';
import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import type { TimelineItem } from '@/models/shared/TimelineItem';
import { emailCredentials } from '@/viewmodels/email/EmailCredentialsStore';
import type { EmailMessageHeader } from '@/api/generated/models/EmailMessageHeader';
import type {
  AdapterRichHeader,
  EmailAdapter,
  ImportantFetchOptions,
} from '@/adapters/email/IEmailAdapter';
import { ProxyEmailAdapter } from '@/adapters/email/ProxyEmailAdapter';
import type { EmailCredentials } from '@/viewmodels/email/EmailCredentialsStore';

interface EmailThreadEntry {
  id: string;
  baseId: string;
  messages: EmailMessageHeader[];
  timestamp: number;
}

const INBOX_ID = 'email-inbox';
const IMPORTANT_ID = 'email-important';
const THREAD_PREFIX = 'email-thread:';

function safeTimestamp(date?: Date): number {
  if (!date) return 0;
  const ts = date.getTime();
  return Number.isNaN(ts) ? 0 : ts;
}

function formatErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === 'string' && error.trim()) return error;
  return 'An unexpected error occurred while fetching email data.';
}

export class EmailViewModel implements IModuleViewModel {
  private static instance: EmailViewModel | null = null;

  private adapter: EmailAdapter;
  private readonly timelineItems = writable<TimelineItem[]>([]);
  private readonly selectedMessages = writable<EmailMessageHeader[]>([]);
  private readonly detailLoading = writable<boolean>(false);
  private readonly detailError = writable<string | null>(null);
  private readonly baseItems = new Map<string, TimelineItem>();
  private threadItems: TimelineItem[] = [];
  private threadCache = new Map<string, EmailThreadEntry>();
  private credentialsUnsub: Unsubscriber | null = null;
  private lastCredentialsFingerprint: string | null = null;

  private constructor(adapter?: EmailAdapter) {
    this.adapter = adapter ?? new ProxyEmailAdapter();
    this.bootstrapBaseTimeline();
  }

  static getInstance(adapter?: EmailAdapter): EmailViewModel {
    if (!EmailViewModel.instance) {
      EmailViewModel.instance = new EmailViewModel(adapter);
    } else if (adapter) {
      EmailViewModel.instance.adapter = adapter;
    }
    return EmailViewModel.instance;
  }

  async initialize(): Promise<void> {
    const initialCreds = get(emailCredentials);
    if (initialCreds) {
      await this.refreshThreads(initialCreds);
    } else {
      this.emitTimeline();
    }

    if (this.credentialsUnsub) {
      this.credentialsUnsub();
      this.credentialsUnsub = null;
    }

    let skipFirst = true;
    this.credentialsUnsub = emailCredentials.subscribe((creds) => {
      if (skipFirst) {
        skipFirst = false;
        return;
      }
      if (!creds) {
        this.lastCredentialsFingerprint = null;
        this.clearEmailState();
        return;
      }
      const fingerprint = this.fingerprintCredentials(creds);
      if (fingerprint === this.lastCredentialsFingerprint) {
        return;
      }
      void this.refreshThreads(creds);
    });
  }

  getTimelineItems(): Readable<TimelineItem[]> {
    return this.timelineItems;
  }

  getSelectedMessages(): Readable<EmailMessageHeader[]> {
    return this.selectedMessages;
  }

  getDetailLoading(): Readable<boolean> {
    return this.detailLoading;
  }

  getDetailError(): Readable<string | null> {
    return this.detailError;
  }

  getModuleName(): string {
    return 'Email';
  }

  getSettingsComponent(): null {
    return null;
  }

  async handleTimelineSelection(item: TimelineItem | null): Promise<void> {
    if (!item) {
      this.selectedMessages.set([]);
      return;
    }

    if (item.id === INBOX_ID) {
      await this.loadAggregate('inbox');
      return;
    }

    if (item.id === IMPORTANT_ID) {
      await this.loadAggregate('important');
      return;
    }

    if (item.id.startsWith(THREAD_PREFIX)) {
      await this.loadThread(item.id);
    }
  }

  async testAndStoreCredentials(credentials: EmailCredentials): Promise<void> {
    const result = await this.adapter.testCredentials(credentials);
    this.selectedMessages.set(this.sortByDescendingDate(result.messages));
    this.detailError.set(null);
    this.updateUnreadCount(INBOX_ID, result.unreadCount);
    emailCredentials.set(credentials);
  }

  private bootstrapBaseTimeline(): void {
    const now = Date.now();
    this.baseItems.set(INBOX_ID, {
      id: INBOX_ID,
      title: 'All Mail',
      description: 'All emails',
      timestamp: now,
      type: 'email',
      unreadCount: 0,
    });
    this.baseItems.set(IMPORTANT_ID, {
      id: IMPORTANT_ID,
      title: 'Important',
      description: 'Important emails',
      timestamp: now - 1,
      type: 'email',
      unreadCount: 0,
    });
    this.emitTimeline();
  }

  private emitTimeline(): void {
    this.timelineItems.set([...this.baseItems.values(), ...this.threadItems]);
  }

  private updateUnreadCount(itemId: string, count: number): void {
    const item = this.baseItems.get(itemId);
    if (!item) return;
    this.baseItems.set(itemId, { ...item, unreadCount: count, timestamp: Date.now() });
    this.emitTimeline();
  }

  private clearEmailState(): void {
    this.threadCache.clear();
    this.threadItems = [];
    this.selectedMessages.set([]);
    this.detailError.set(null);
    this.emitTimeline();
  }

  private async loadAggregate(kind: 'inbox' | 'important'): Promise<void> {
    const creds = get(emailCredentials);
    if (!creds) {
      this.selectedMessages.set([]);
      this.detailError.set('Email credentials are required.');
      return;
    }

    this.detailLoading.set(true);
    this.detailError.set(null);

    try {
      const result =
        kind === 'inbox'
          ? await this.adapter.fetchMailbox(creds, { mailbox: 'INBOX' })
          : await this.adapter.fetchMailbox(creds, this.buildImportantFetchOptions(creds));
      this.selectedMessages.set(this.sortByDescendingDate(result.messages));
      this.updateUnreadCount(kind === 'inbox' ? INBOX_ID : IMPORTANT_ID, result.unreadCount);
    } catch (error) {
      this.selectedMessages.set([]);
      this.detailError.set(formatErrorMessage(error));
    } finally {
      this.detailLoading.set(false);
    }
  }

  private async loadThread(threadId: string): Promise<void> {
    const cached = this.threadCache.get(threadId);
    if (cached) {
      this.detailError.set(null);
      this.detailLoading.set(false);
      this.selectedMessages.set(cached.messages);
      return;
    }

    const creds = get(emailCredentials);
    if (!creds) {
      this.detailError.set('Email credentials are required.');
      this.selectedMessages.set([]);
      return;
    }

    this.detailLoading.set(true);
    this.detailError.set(null);

    try {
      await this.refreshThreads(creds);
      const refreshed = this.threadCache.get(threadId);
      if (refreshed) {
        this.selectedMessages.set(refreshed.messages);
      } else {
        this.selectedMessages.set([]);
        this.detailError.set('Unable to locate messages for this thread.');
      }
    } catch (error) {
      this.selectedMessages.set([]);
      this.detailError.set(formatErrorMessage(error));
    } finally {
      this.detailLoading.set(false);
    }
  }

  private async refreshThreads(credentials: EmailCredentials): Promise<void> {
    let headers: AdapterRichHeader[] = [];
    try {
      headers = await this.adapter.fetchRecentHeaders(credentials);
    } catch (error) {
      console.error('EmailViewModel: failed to fetch email headers', error);
      return;
    }

    this.buildThreadsFromHeaders(headers);
    this.lastCredentialsFingerprint = this.fingerprintCredentials(credentials);
  }

  private buildThreadsFromHeaders(headers: AdapterRichHeader[]): void {
    const grouped = new Map<
      string,
      { latest?: AdapterRichHeader; messages: AdapterRichHeader[]; seen: Set<string> }
    >();

    for (const header of headers) {
      const baseId = this.deriveThreadBase(header);
      if (!baseId) continue;
      const dedupeKey = this.getMessageKey(header);
      let group = grouped.get(baseId);
      if (!group) {
        group = { latest: undefined, messages: [], seen: new Set<string>() };
        grouped.set(baseId, group);
      }
      if (group.seen.has(dedupeKey)) {
        continue;
      }
      group.seen.add(dedupeKey);
      group.messages.push(header);
      if (!group.latest || safeTimestamp(header.date) > safeTimestamp(group.latest.date)) {
        group.latest = header;
      }
    }

    const threadItems: TimelineItem[] = [];
    const cache = new Map<string, EmailThreadEntry>();

    grouped.forEach((group, baseId) => {
      if (!group.latest || group.messages.length === 0) {
        return;
      }

      if (group.messages.length < 2 && !this.isReplySubject(group.latest.subject)) {
        return;
      }

      const threadId = `${THREAD_PREFIX}${encodeURIComponent(baseId)}`;
      const sortedMessages = this.sortByDescendingDate(
        group.messages.map((msg) => this.toEmailMessageHeader(msg))
      );

      const latestTs = safeTimestamp(group.latest.date);

      threadItems.push({
        id: threadId,
        title: group.latest.subject || '(no subject)',
        description: group.latest.from || '',
        timestamp: latestTs,
        type: 'email',
        unreadCount: 0,
      });

      cache.set(threadId, {
        id: threadId,
        baseId,
        messages: sortedMessages,
        timestamp: latestTs,
      });
    });

    threadItems.sort((a, b) => b.timestamp - a.timestamp);
    this.threadItems = threadItems;
    this.threadCache = cache;
    this.emitTimeline();
  }

  private deriveThreadBase(header: AdapterRichHeader): string | null {
    if (!header) return null;
    if (header.references && header.references.length > 0) {
      const first = header.references[0]?.trim();
      if (first) return first.toLowerCase();
    }
    if (header.inReplyTo) {
      const reply = header.inReplyTo.trim();
      if (reply) return reply.toLowerCase();
    }
    if (header.messageId) {
      return header.messageId.trim().toLowerCase();
    }
    return null;
  }

  private getMessageKey(header: AdapterRichHeader): string {
    const id = header.messageId?.trim().toLowerCase();
    if (id) return id;
    const subject = header.subject?.trim().toLowerCase() ?? '';
    const ts = safeTimestamp(header.date);
    return `${subject}|${ts}`;
  }

  private toEmailMessageHeader(header: AdapterRichHeader): EmailMessageHeader {
    return {
      from: header.from,
      subject: header.subject,
      date: header.date ? new Date(header.date.getTime()) : undefined,
    };
  }

  private isReplySubject(subject?: string): boolean {
    if (!subject) return false;
    return /^re:\s*/i.test(subject.trim());
  }

  private fingerprintCredentials(credentials: EmailCredentials): string {
    return `${credentials.host}:${credentials.port}:${credentials.email}`;
  }

  private sortByDescendingDate(messages: EmailMessageHeader[]): EmailMessageHeader[] {
    return messages.slice().sort((a, b) => safeTimestamp(b.date) - safeTimestamp(a.date));
  }

  private buildImportantFetchOptions(credentials: EmailCredentials): ImportantFetchOptions {
    if (this.isLikelyGmailAccount(credentials)) {
      return { mailbox: '[Gmail]/Important' };
    }
    return { mailbox: 'INBOX', searchFlags: ['\\Flagged'] };
  }

  private isLikelyGmailAccount(credentials: EmailCredentials): boolean {
    const host = (credentials.host ?? '').toLowerCase();
    const emailDomain = credentials.email.split('@')[1]?.toLowerCase() ?? '';
    return (
      host.includes('gmail') ||
      emailDomain.endsWith('gmail.com') ||
      emailDomain.endsWith('googlemail.com')
    );
  }
}
