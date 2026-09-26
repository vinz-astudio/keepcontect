import { useEffect, useState } from 'react'
import { useI18n } from '@/lib/i18n'
import { isTauri } from '@/lib/platform'
import { getTauriEvidenceStatus } from './shadowCoverage'
import '@/features/baseline/ProtectionHealthCard.css'

/** Local failure remains visible even before a server health read succeeds. */
export function TauriCollectorNotice() {
  const { lang } = useI18n()
  const [status, setStatus] = useState(getTauriEvidenceStatus)
  useEffect(() => {
    if (!isTauri()) return
    const refresh = () => setStatus(getTauriEvidenceStatus())
    window.addEventListener('kc-tauri-evidence-status', refresh)
    refresh()
    return () => window.removeEventListener('kc-tauri-evidence-status', refresh)
  }, [])
  if (!isTauri() || status.state !== 'limited') return null
  const zh = lang === 'zh'
  const reconnect = ['revoked', 'unregistered_binding', 'credential_mismatch', 'collector_unavailable'].includes(status.reason)
  return (
    <section className="health health--limited" role="status" aria-live="polite">
      <p className="health__state">{zh ? '这台电脑的采集受限' : 'This computer: Limited collection'}</p>
      <p className="health__detail">
        {reconnect
          ? (zh ? '请关闭再开启电脑鼠标键盘采集，以重新连接这台设备。' : 'Turn Computer Mouse/Keyboard Activity off and on to reconnect this device.')
          : (zh ? '暂时无法确认这台电脑的活动采集正常，KC 会自动重试。' : 'Activity collection on this computer is not yet verified. KC will retry automatically.')}
        {' '}{zh ? '漏签计数仍会继续。' : 'Miss counting continues.'}
      </p>
    </section>
  )
}
