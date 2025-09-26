import { registerPlugin } from '@capacitor/core';

export interface InitCryptoOptions {
  userId: string;
  deviceId: string;
  cachePath?: string;
}

export interface DecryptEventOptions {
  eventJson: string;
  roomId: string;
  handleVerificationEvents?: boolean;
  strictShields?: boolean;
}

export interface DecryptEventResult {
  clearEvent: string;
  senderCurve25519Key: string;
  claimedEd25519Key?: string | null;
  forwardingCurve25519Chain: string[];
  shieldState: {
    color: string;
    code?: string | null;
    message?: string | null;
  };
}

export interface MatrixCryptoPlugin {
  initCrypto(options: InitCryptoOptions): Promise<void>;
  decryptEvent(options: DecryptEventOptions): Promise<DecryptEventResult>;
}

export const MatrixCrypto = registerPlugin<MatrixCryptoPlugin>('MatrixCrypto', {
  web: () => import('./web/MatrixCryptoWeb').then((m) => new m.MatrixCryptoWeb()),
});
