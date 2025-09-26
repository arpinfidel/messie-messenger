import { registerPlugin } from '@capacitor/core';

import type { NativeCryptoPlugin } from './definitions';

const NativeCrypto = registerPlugin<NativeCryptoPlugin>('NativeCrypto', {
  web: () => import('./web').then((m) => new m.NativeCryptoWeb()),
});

export * from './definitions';
export { NativeCrypto };
