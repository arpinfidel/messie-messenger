export interface MatrixReplyContext {
  eventId: string;
  sender?: string;
  senderDisplayName?: string;
  body?: string;
  msgtype?: string;
  fallbackSender?: string;
  fallbackBody?: string;
}
