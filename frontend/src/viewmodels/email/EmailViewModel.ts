import { get, writable, type Readable } from 'svelte/store';
import type { IModuleViewModel } from '@/viewmodels/shared/IModuleViewModel';
import type { TimelineItem } from '@/models/shared/TimelineItem';
import { emailCredentials } from '@/viewmodels/email/EmailCredentialsStore';
import type { EmailMessageHeader } from '@/api/generated/models/EmailMessageHeader';

export class EmailViewModel implements IModuleViewModel {
  private static instance: EmailViewModel | null = null;
  private timelineItems = writable<TimelineItem[]>([]);
  private threadsCursor: number | null = null;
  private selectedMessages = writable<EmailMessageHeader[]>([]);
  private fallbackMessages: EmailMessageHeader[] = [];
  private grouped: Map<string, EmailMessageHeader[]> = new Map();
  private makeBase(m: any): string {
    const refs: string[] = Array.isArray(m?.references) ? m.references : [];
    if (refs.length > 0) return String(refs[0]);
    if (m?.inReplyTo) return String(m.inReplyTo);
    return String(m?.messageId || '');
  }

  static getInstance(): EmailViewModel {
    if (!EmailViewModel.instance) {
      EmailViewModel.instance = new EmailViewModel();
    }
    return EmailViewModel.instance;
  }

  async initialize(): Promise<void> {
    const now = Date.now();
    // Bootstrap with the two aggregate entries
    this.timelineItems.set([
      {
        id: 'email-inbox',
        title: 'All Mail',
        description: 'All non-important emails',
        timestamp: now,
        type: 'email',
        unreadCount: 0,
      },
      {
        id: 'email-important',
        title: 'Important',
        description: 'Important emails',
        timestamp: now - 1,
        type: 'email',
        unreadCount: 0,
      },
    ]);

    // If credentials are already present, fetch threads immediately; otherwise wait for login
    const creds = get(emailCredentials);
    if (creds) {
      await this.fetchThreads();
    }
    emailCredentials.subscribe(async (c) => {
      if (c) {
        await this.fetchThreads();
      }
    });
  }

  getTimelineItems(): Readable<TimelineItem[]> {
    return this.timelineItems;
  }

  updateUnreadCount(itemId: string, count: number): void {
    this.timelineItems.update((items) =>
      items.map((it) => (it.id === itemId ? { ...it, unreadCount: count } : it))
    );
  }

  getSelectedMessages(): Readable<EmailMessageHeader[]> {
    return this.selectedMessages;
  }

  async openThread(itemId: string): Promise<void> {
    const prefix = 'email-thread:';
    if (!itemId.startsWith(prefix)) return;
    const base = decodeURIComponent(itemId.slice(prefix.length));
    // Clear current messages before loading new thread
    this.selectedMessages.set([]);
    await this.refreshThreadMessagesByBase(base);
  }

  private async fetchThreads(): Promise<void> {
    const creds = get(emailCredentials);
    if (!creds) return;
    // Use proxy headers endpoint and group client-side
    const url = `/api/v1/email/headers`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(creds),
    });
    if (!res.ok) {
      console.error('Failed to fetch email threads');
      return;
    }
    const data = await res.json();
    const msgs: any[] = Array.isArray(data?.messages) ? data.messages : [];
    const byKey: Map<string, { latestTs: number; subject: string; from: string; count: number; messages: EmailMessageHeader[]; seen: Set<string> }>= new Map();
    for (const m of msgs) {
      const base = this.makeBase(m);
      if (!base) continue;
      const ts = m?.date ? new Date(m.date).getTime() : Date.now();
      const subject = typeof m?.subject === 'string' ? m.subject : '';
      const from = typeof m?.from === 'string' ? m.from : '';
      const midRaw = typeof m?.messageId === 'string' ? m.messageId : '';
      const mid = midRaw ? midRaw.trim().toLowerCase() : `${subject}|${ts}`; // fallback key
      const eh: EmailMessageHeader = { from, subject, date: m?.date ? new Date(m.date) : undefined } as any;
      const g = byKey.get(base) || { latestTs: 0, subject: '', from: '', count: 0, messages: [], seen: new Set<string>() };
      if (g.seen.has(mid)) {
        byKey.set(base, g);
        continue; // dedupe messages across folders
      }
      g.seen.add(mid);
      g.count += 1;
      g.messages.push(eh);
      if (ts > g.latestTs) {
        g.latestTs = ts;
        g.subject = subject;
        g.from = from;
      }
      byKey.set(base, g);
    }
    this.grouped = new Map();
    const items: TimelineItem[] = [];
    for (const [base, g] of byKey) {
      if (g.count < 2 && !/^re:\s*/i.test(g.subject)) continue; // hide singletons
      this.grouped.set(base, g.messages.sort((a, b) => (new Date(a.date || 0).getTime() - new Date(b.date || 0).getTime())));
      items.push({
        id: `email-thread:${encodeURIComponent(base)}`,
        title: g.subject || '(no subject)',
        description: g.from || '',
        timestamp: g.latestTs,
        type: 'email',
        unreadCount: 0,
      });
    }
    const newItems = items;
    this.threadsCursor = Number.isFinite(data?.cursor) ? Number(data.cursor) : null;

    // Merge: keep the two fixed entries, then replace any existing thread entries.
    this.timelineItems.update((items) => {
      const fixed = items.filter((it) => it.id === 'email-inbox' || it.id === 'email-important');
      const combined = [...fixed, ...newItems];
      // Deduplicate by id to avoid duplicates if called multiple times
      const seen = new Set<string>();
      const unique: TimelineItem[] = [];
      for (const it of combined) {
        if (seen.has(it.id)) continue;
        seen.add(it.id);
        unique.push(it);
      }
      return unique;
    });
  }

  private async fetchThreadMessages(threadKey: string): Promise<void> {
    // Deprecated: threadKey-based fetch removed; use refreshThreadMessagesByBase instead.
    const base = decodeURIComponent(threadKey);
    await this.refreshThreadMessagesByBase(base);
  }

  private async refreshThreadMessagesByBase(base: string): Promise<void> {
    // First try to use already grouped messages
    const local = this.grouped.get(base);
    if (local && local.length > 0) {
      this.selectedMessages.set(local);
      return;
    }
    // Fallback: re-fetch headers, regroup, and pick requested base
    const url = `/api/v1/email/headers`;
    const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(get(emailCredentials)) });
    if (!res.ok) {
      console.error('Failed to refresh thread headers');
      return;
    }
    const data = await res.json();
    const msgs: any[] = Array.isArray(data?.messages) ? data.messages : [];
    const collected: EmailMessageHeader[] = [];
    const seen = new Set<string>();
    for (const m of msgs) {
      const b = this.makeBase(m);
      if (b !== base) continue;
      const ts = m?.date ? new Date(m.date).getTime() : Date.now();
      const subject = typeof m?.subject === 'string' ? m.subject : '';
      const midRaw = typeof m?.messageId === 'string' ? m.messageId : '';
      const mid = midRaw ? midRaw.trim().toLowerCase() : `${subject}|${ts}`;
      if (seen.has(mid)) continue;
      seen.add(mid);
      collected.push({
        from: typeof m?.from === 'string' ? m.from : undefined,
        subject,
        date: m?.date ? new Date(m.date) : undefined,
      } as any);
    }
    collected.sort((a, b) => (new Date(a.date || 0).getTime() - new Date(b.date || 0).getTime()));
    this.selectedMessages.set(collected);
  }

  private normalizeSubject(subj: string): string {
    let s = subj || '';
    // Strip common reply/forward prefixes repeatedly
    for (;;) {
      const prev = s;
      s = s.replace(/^(re|fw|fwd):\s*/i, '');
      if (s === prev) break;
    }
    return s.trim().toLowerCase();
  }

  setSelectedMessages(messages: EmailMessageHeader[]): void {
    this.selectedMessages.set(messages || []);
  }

  getModuleName(): string {
    return 'Email';
  }

  getSettingsComponent(): null {
    return null;
  }
}
