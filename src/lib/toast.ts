// 轻量应用内 toast：替代原生 alert（不打断、可读、风格统一）。

export type ToastKind = 'ok' | 'info' | 'danger'
export interface ToastItem {
  id: number
  msg: string
  kind: ToastKind
}

const listeners = new Set<(t: ToastItem) => void>()
let seq = 0

export function toast(msg: string, kind: ToastKind = 'info'): void {
  const item: ToastItem = { id: ++seq, msg, kind }
  listeners.forEach((l) => l(item))
}

export function onToast(cb: (t: ToastItem) => void): () => void {
  listeners.add(cb)
  return () => listeners.delete(cb)
}
