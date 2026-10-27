import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The API is always called at the relative path /api. In production CloudFront
// proxies it to the ALB; locally the dev server does, to the docker-compose
// backend unless API_PROXY_TARGET points somewhere else.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 4100,
    proxy: {
      '/api': {
        target: process.env.API_PROXY_TARGET || 'http://localhost:8000',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'build',
    // CloudFront's SPA rewrite and the S3 cache headers key off /static/.
    assetsDir: 'static',
  },
});
