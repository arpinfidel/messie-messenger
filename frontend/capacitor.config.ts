import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.messie.messenger',
  appName: 'Messie Messenger',
  webDir: 'dist',
  bundledWebRuntime: false,
  server: {
    androidScheme: 'http',
  },
};

export default config;
