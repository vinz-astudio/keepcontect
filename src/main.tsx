import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from '@/App'
import '@/features/install/installPrompt' // 尽早注册 beforeinstallprompt 捕获
import '@/index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

// PWA：注册 Service Worker（Web Push 与离线壳的载体）
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {})

  // 监听 controllerchange 事件：当后台发现新版本 Service Worker 并激活（skipWaiting）后，
  // 页面自动重载刷新，实现完全无缝、免人工点击的“热更新”。
  let refreshing = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!refreshing) {
      refreshing = true
      window.location.reload()
    }
  })
}
