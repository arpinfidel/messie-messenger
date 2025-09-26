import type { PluginListenerHandle } from '@capacitor/core';

export type InitOptions = {
  userId: string;
  deviceId: string;
  homeserverUrl: string;
  dataPath: string;
};

export type EncryptEventRequest = {
  handleId: string;
  roomId: string;
  eventType: string;
  contentJson: string;
};

export type EncryptEventResponse = {
  eventJson: string;
};

export type DecryptEventRequest = {
  handleId: string;
  roomId: string;
  eventJson: string;
};

export type DecryptEventResponse = {
  clearEventJson: string;
  wasEncrypted: boolean;
  senderCurve25519Key?: string;
  claimedEd25519Key?: string;
};

export type VerificationStatus = {
  userId: string;
  isVerified: boolean;
};

export interface NativeCryptoPlugin {
  readonly platform: 'android' | 'ios' | 'web' | 'unknown';

  init(options: InitOptions): Promise<{ handleId: string }>;
  encryptEvent(request: EncryptEventRequest): Promise<EncryptEventResponse>;
  decryptEvent(request: DecryptEventRequest): Promise<DecryptEventResponse>;
  downloadKeys(params: { handleId: string; userIds: string[] }): Promise<void>;
  refreshDeviceLists(params: { handleId: string }): Promise<void>;
  getUserVerificationStatus(params: { handleId: string; userId: string }): Promise<VerificationStatus>;
  setDeviceVerified(params: {
    handleId: string;
    userId: string;
    deviceId: string;
    verified: boolean;
  }): Promise<void>;
  flush(params: { handleId: string }): Promise<void>;
  close(params: { handleId: string }): Promise<void>;

  addListener(eventName: 'nativeCryptoLog', listenerFunc: (data: { level: string; message: string }) => void):
    | PluginListenerHandle
    | Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}
