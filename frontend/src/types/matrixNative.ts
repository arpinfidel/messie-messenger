export interface MatrixNativeCryptoBundle {
  userId?: string;
  deviceId?: string;
  accountPickle?: string;
  identityKeys?: {
    curve25519?: string;
    ed25519?: string;
  };
  olmSessions?: Array<{
    senderKey: string;
    sessionId: string;
    pickle: string;
  }>;
  inboundGroupSessions?: Array<{
    roomId: string;
    senderKey: string;
    sessionId: string;
    pickle: string;
  }>;
  outboundGroupSessions?: Array<{
    roomId: string;
    sessionId: string;
    pickle: string;
  }>;
  secrets?: Record<string, string>;
  backup?: {
    info?: Record<string, unknown> | null;
    privateKey?: string;
  };
  roomKeys?: Array<Record<string, unknown>>;
  secretStorageDefaultKeyId?: string | null;
}
