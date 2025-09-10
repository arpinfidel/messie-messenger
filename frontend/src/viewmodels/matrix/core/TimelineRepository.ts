import * as matrixSdk from 'matrix-js-sdk';

export interface RepoEvent {
  eventId: string;
  roomId: string;
  type: string; // SDK event.getType()
  sender: string;
  originServerTs: number;
  /**
   * Monotonically increasing index used for pagination. Timestamp ordering is
   * not reliable when backfilling events, so we assign a custom 64‑bit integer
   * to each event to preserve insertion order.
   */
  index: number;
  content: matrixSdk.IContent; // clear or encrypted content
  unsigned?: any;
}

export interface PageResult {
  events: RepoEvent[];
  fromToken: string | null;
  toToken: string | null; // next backward token
}
