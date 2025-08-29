import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { fileURLToPath, URL } from 'node:url';

// https://vite.dev/config/
export default defineConfig({
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
})
