import { useState } from 'react'
import { Icon } from '@/features/common/Icon'
import { useI18n } from '@/lib/i18n'
import {
  clearViewportTrace,
  exportViewportTraceText,
  readViewportTrace,
  recordViewportTrace,
} from '@/lib/viewportDiagnostics'

export function ViewportDiagnosticsCard() {
  const { lang } = useI18n()
  const [count, setCount] = useState(() => readViewportTrace().length)
  const [status, setStatus] = useState('')

  const refresh = () => setCount(readViewportTrace().length)

  const copy = async () => {
    recordViewportTrace('manual-copy-viewport-diagnostics')
    const text = exportViewportTraceText()
    try {
      await navigator.clipboard.writeText(text)
      setStatus(lang === 'zh' ? '已复制诊断日志' : 'Diagnostics copied')
    } catch {
      const box = document.createElement('textarea')
      box.value = text
      box.style.position = 'fixed'
      box.style.left = '-9999px'
      document.body.appendChild(box)
      box.focus()
      box.select()
      const ok = document.execCommand('copy')
      box.remove()
      setStatus(ok ? (lang === 'zh' ? '已复制诊断日志' : 'Diagnostics copied') : (lang === 'zh' ? '复制失败，请再试一次' : 'Copy failed; try again'))
    }
    refresh()
    window.setTimeout(() => setStatus(''), 1800)
  }

  const clear = () => {
    clearViewportTrace()
    refresh()
    setStatus(lang === 'zh' ? '已清空' : 'Cleared')
    window.setTimeout(() => setStatus(''), 1200)
  }

  return (
    <section className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
      <h2 className="card__title" style={{ margin: 0 }}>
        <Icon name="signal" />
        {lang === 'zh' ? '布局诊断' : 'Layout diagnostics'}
      </h2>
      <p className="muted" style={{ margin: 0, fontSize: '0.84rem' }}>
        {lang === 'zh'
          ? '如果底部 navbar 下方再次出现空白，先不要关闭 App；到这里复制日志给我。日志只保存在本机，不会自动上传。'
          : 'If the bottom navbar gap appears again, do not close the app first. Copy this local-only log and send it over.'}
      </p>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '10px', flexWrap: 'wrap' }}>
        <span className="muted" style={{ margin: 0, fontSize: '0.78rem' }}>
          {lang === 'zh' ? `已记录 ${count} 条` : `${count} entries recorded`}
        </span>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
          <button className="share" onClick={() => void copy()}>
            {lang === 'zh' ? '复制日志' : 'Copy log'}
          </button>
          <button className="share" onClick={clear} style={{ background: 'var(--bg)', color: 'var(--fg-muted)', borderColor: 'var(--line)' }}>
            {lang === 'zh' ? '清空' : 'Clear'}
          </button>
        </div>
      </div>
      {status && <p className="muted" style={{ margin: 0, fontSize: '0.78rem', color: 'var(--accent)' }}>{status}</p>}
    </section>
  )
}
