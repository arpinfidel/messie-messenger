import { WebPlugin } from '@capacitor/core';
import type {
  DecryptEventOptions,
  DecryptEventResult,
  InitCryptoOptions,
  MatrixCryptoPlugin,
} from '../MatrixCryptoPlugin';

export class MatrixCryptoWeb extends WebPlugin implements MatrixCryptoPlugin {
  async initCrypto(_options: InitCryptoOptions): Promise<void> {
    this.logger?.warn('MatrixCryptoWeb.initCrypto is a no-op on web');
  }

  async decryptEvent(_options: DecryptEventOptions): Promise<DecryptEventResult> {
    throw this.unimplemented('decryptEvent not available on web');
  }
}
