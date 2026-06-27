import { useCallback, useEffect, useState } from 'react'
import {
  countTodayPings,
  getHeartbeatToken,
  lastPingAt,
} from '@/features/passive/api'
import { getAllSignals } from '@/features/signals/store'
import { translate, useI18n } from '@/lib/i18n'
import './PassiveSignalCard.css'

function ago(iso: string): string {
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return translate('time.now')
  if (s < 3600) return translate('time.min', { n: Math.floor(s / 60) })
  if (s < 86400) return translate('time.hour', { n: Math.floor(s / 3600) })
  return translate('time.day', { n: Math.floor(s / 86400) })
}

/**
 * 守护活跃度（今日上报次数 / 最近活跃时间）。原在 Me 页的被动感知卡内，
 * 现搬到「作息」页短期组顶部——这是最贴近当下、用户最关心的一块。
 * 数据全在端上由本地 signals 计算，绝不上传，与「判断完全线下」一致。
 */
export function ActiveStatusBox() {
  const { t, lang } = useI18n()
  const [todayCount, setTodayCount] = useState(0)
  const [lastAt, setLastAt] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const tok = await getHeartbeatToken()
      if (!tok) return
      const localEvents = await getAllSignals()
      const ps = localEvents.map((e) => ({
        id: 0,
        user_id: '',
        kind: e.kind,
        at: new Date(e.t).toISOString(),
        created_at: new Date(e.t).toISOString(),
      }))
      setTodayCount(countTodayPings(ps))
      setLastAt(lastPingAt(ps))
    } catch {
      /* 忽略：活跃度展示不阻塞页面 */
    }
  }, [])

  useEffect(() => {
    void load()
    const timer = setInterval(() => void load(), 30000)
    return () => clearInterval(timer)
  }, [load])

  return (
    <div className="psig__status-box" style={{ margin: 0 }}>
      <div className="psig__status-header">
        <strong>{lang === 'zh' ? '守护活跃度' : 'Active Status'}</strong>
        <span className="psig__status-badge">
          {todayCount > 0
            ? lang === 'zh'
              ? '运行中'
              : 'Running'
            : lang === 'zh'
              ? '待活跃'
              : 'Idle'}
        </span>
      </div>

      <div className="psig__status-grid">
        <div className="psig__status-cell">
          <span className="psig__status-label">
            {lang === 'zh' ? '今日上报次数' : 'Today Pings'}
          </span>
          <span className="psig__status-value">{todayCount}</span>
        </div>
        <div className="psig__status-cell">
          <span className="psig__status-label">
            {lang === 'zh' ? '最近活跃时间' : 'Last Active'}
          </span>
          <span className="psig__status-value psig__status-value--time">
            {lastAt ? t('passive.last', { ago: ago(lastAt) }) : t('passive.never')}
          </span>
        </div>
      </div>
    </div>
  )
}
