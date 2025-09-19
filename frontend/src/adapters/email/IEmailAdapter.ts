import type { EmailMessageHeader } from '@/api/generated/models/EmailMessageHeader';
import type { EmailCredentials } from '@/viewmodels/email/EmailCredentialsStore';

export interface EmailListResult {
  messages: EmailMessageHeader[];
  unreadCount: number;
}

export interface AdapterRichHeader {
  from?: string;
  subject?: string;
  date?: Date;
  messageId: string;
  inReplyTo?: string;
  references: string[];
}

export interface ImportantFetchOptions {
  mailbox?: string;
  searchFlags?: string[];
}

export interface EmailAdapter {
  testCredentials(credentials: EmailCredentials): Promise<EmailListResult>;
  fetchMailbox(
    credentials: EmailCredentials,
    options?: ImportantFetchOptions
  ): Promise<EmailListResult>;
  fetchRecentHeaders(credentials: EmailCredentials): Promise<AdapterRichHeader[]>;
}
