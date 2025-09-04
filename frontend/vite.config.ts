import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { fileURLToPath, URL } from 'node:url';
import process from 'node:process';

// https://vite.dev/config/
export default defineConfig({
  define: {
    USE_MATRIX_LITE: JSON.stringify(process.env.VITE_USE_MATRIX_LITE === '1'),
  },
  plugins: [svelte()],
  server: {
    headers: {
      // 'Cross-Origin-Opener-Policy': 'same-origin',
      // 'Cross-Origin-Embedder-Policy': 'require-corp',
    },
    watch: {
      usePolling: true,
    },
  },
  optimizeDeps: {
    exclude: ['@matrix-org/matrix-sdk-crypto-wasm'],
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
});
