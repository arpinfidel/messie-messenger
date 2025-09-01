import * as matrixSdk from 'matrix-js-sdk';

export interface RepoEvent {
  eventId: string;
  roomId: string;
  type: string; // SDK event.getType()
  sender: string;
  originServerTs: number;
  content: matrixSdk.IContent; // clear or encrypted content
  unsigned?: any;
}

export interface PageResult {
  events: RepoEvent[];
  fromToken: string | null;
  toToken: string | null; // next backward token
}
