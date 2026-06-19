import { useEffect, useState } from 'react'
import { onToast, type ToastItem } from '@/lib/toast'
import './ToastHost.css'

export function ToastHost() {
  const [items, setItems] = useState<ToastItem[]>([])

  useEffect(
    () =>
      onToast((t) => {
        setItems((s) => [...s, t])
        window.setTimeout(
          () => setItems((s) => s.filter((x) => x.id !== t.id)),
          3600,
        )
      }),
    [],
  )

  if (items.length === 0) return null
  return (
    <div className="toasts" role="status" aria-live="polite">
      {items.map((t) => (
        <div key={t.id} className={`toast toast--${t.kind}`}>
          {t.msg}
        </div>
      ))}
    </div>
  )
}
