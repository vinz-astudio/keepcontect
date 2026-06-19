import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    host: true,
  },
  build: {
    outDir: 'dist',
    rollupOptions: {
      output: {
        // 拆出大依赖：与 app 代码并行下载、独立缓存（更新 app 时 vendor 命中缓存）
        manualChunks: {
          react: ['react', 'react-dom'],
          supabase: ['@supabase/supabase-js', '@supabase/ssr'],
        },
      },
    },
  },
})
