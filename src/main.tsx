import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from '@/App'
import '@/features/install/installPrompt' // 尽早注册 beforeinstallprompt 捕获
import '@fontsource-variable/plus-jakarta-sans'
import '@material-symbols/font-400/rounded.css'
import '@/index.css'
import { installViewportDiagnostics, recordViewportTrace } from '@/lib/viewportDiagnostics'

installViewportDiagnostics()
recordViewportTrace('main-before-render')

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
recordViewportTrace('main-after-render')

// PWA：注册 Service Worker（Web Push 与离线壳的载体）
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').then(() => recordViewportTrace('service-worker-registered')).catch(() => {})

  // 监听 controllerchange 事件：在浏览器模式下热更新刷新，但在 iOS PWA Standalone 模式下静默更新，避免 iOS 主屏快捷方式无限重载崩溃。
  let refreshing = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    const isStandalone = (window.navigator as any).standalone || window.matchMedia('(display-mode: standalone)').matches
    if (!refreshing && !isStandalone) {
      refreshing = true
      recordViewportTrace('service-worker-controllerchange')
      window.location.reload()
    }
  })
}
