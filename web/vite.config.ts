import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// Dev only: `npm run dev` proxies the API to the Rust server on loopback.
// Production serves the built `dist/` straight from the Rust binary.
export default defineConfig({
  plugins: [svelte()],
  server: {
    proxy: {
      '/api': { target: 'http://127.0.0.1:8080', ws: true },
    },
  },
});
