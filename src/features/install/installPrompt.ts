// 捕获 Android/Chrome 的 beforeinstallprompt（可能在 React 挂载前触发），
// 存起来供 "Get App" 按钮调用。iOS 不支持该事件，走"添加到主屏"图文引导。

interface BIPEvent extends Event {
  prompt: () => void
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

let deferred: BIPEvent | null = null
const listeners = new Set<() => void>()

function emit() {
  listeners.forEach((l) => l())
}

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault()
  deferred = e as BIPEvent
  emit()
})

window.addEventListener('appinstalled', () => {
  deferred = null
  emit()
})

export function canInstall(): boolean {
  return deferred !== null
}

export function onInstallChange(cb: () => void): () => void {
  listeners.add(cb)
  return () => listeners.delete(cb)
}

export async function promptInstall(): Promise<boolean> {
  if (!deferred) return false
  deferred.prompt()
  const { outcome } = await deferred.userChoice
  deferred = null
  emit()
  return outcome === 'accepted'
}
