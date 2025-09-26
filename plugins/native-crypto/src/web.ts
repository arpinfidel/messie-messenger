import { WebPlugin } from '@capacitor/core';

import type {
  DecryptEventRequest,
  DecryptEventResponse,
  EncryptEventRequest,
  EncryptEventResponse,
  NativeCryptoPlugin,
  VerificationStatus,
} from './definitions';

export class NativeCryptoWeb extends WebPlugin implements NativeCryptoPlugin {
  readonly platform = 'web' as const;

  async init(): Promise<{ handleId: string }> {
    throw this.unimplemented('Native crypto is not available on web.');
  }

  async encryptEvent(_: EncryptEventRequest): Promise<EncryptEventResponse> {
    throw this.unimplemented('Native crypto encryptEvent not implemented on web.');
  }

  async decryptEvent(_: DecryptEventRequest): Promise<DecryptEventResponse> {
    throw this.unimplemented('Native crypto decryptEvent not implemented on web.');
  }

  async downloadKeys(): Promise<void> {
    throw this.unimplemented('Native crypto downloadKeys not implemented on web.');
  }

  async refreshDeviceLists(): Promise<void> {
    throw this.unimplemented('Native crypto refreshDeviceLists not implemented on web.');
  }

  async getUserVerificationStatus(): Promise<VerificationStatus> {
    throw this.unimplemented('Native crypto verification status not implemented on web.');
  }

  async setDeviceVerified(): Promise<void> {
    throw this.unimplemented('Native crypto setDeviceVerified not implemented on web.');
  }

  async flush(): Promise<void> {
    throw this.unimplemented('Native crypto flush not implemented on web.');
  }

  async close(): Promise<void> {
    throw this.unimplemented('Native crypto close not implemented on web.');
  }
}
