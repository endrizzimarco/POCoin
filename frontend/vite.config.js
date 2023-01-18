import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  css: {
    preprocessorOptions: {
      less: {
        modifyVars: { '@primary-color': '#1DA57A', '@font-size-base': '12px' },
        javascriptEnabled: true,
        additionalData: '@root-entry-name: default;'
      }
    }
  }
})
