export interface BehaviorTimeDisplay {
  relative: string
  exact: string
}

export function formatBehaviorTime(
  iso: string | null | undefined,
  nowMs = Date.now(),
  lang = 'en',
  timeZone?: string,
): BehaviorTimeDisplay {
  if (!iso) {
    return {
      relative: lang === 'zh' ? '暂无行为' : 'No behavior yet',
      exact: '',
    }
  }

  const time = new Date(iso).getTime()
  if (!Number.isFinite(time)) {
    return {
      relative: lang === 'zh' ? '时间无效' : 'Invalid time',
      exact: iso,
    }
  }

  const elapsedSeconds = Math.max(0, Math.floor((nowMs - time) / 1000))
  let relative: string
  if (elapsedSeconds < 60) {
    relative = lang === 'zh' ? '刚刚' : 'just now'
  } else if (elapsedSeconds < 3600) {
    const minutes = Math.floor(elapsedSeconds / 60)
    relative = lang === 'zh' ? `${minutes}分钟前` : `${minutes}m ago`
  } else if (elapsedSeconds < 86400) {
    const hours = Math.floor(elapsedSeconds / 3600)
    relative = lang === 'zh' ? `${hours}小时前` : `${hours}h ago`
  } else {
    const days = Math.floor(elapsedSeconds / 86400)
    relative = lang === 'zh' ? `${days}天前` : `${days}d ago`
  }

  const date = new Date(time)
  const exact = new Intl.DateTimeFormat(lang === 'zh' ? 'zh-CN' : 'en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone,
  }).format(date)

  return { relative, exact }
}