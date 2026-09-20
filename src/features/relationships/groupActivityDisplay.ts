import type { ActivityStatus } from '@/features/relationships/groupActivity'

export function formatGroupActivityStatus(
  status: ActivityStatus,
  hours: number | null,
  lang = 'en',
): string {
  const zh = lang === 'zh'
  const h = Math.max(0, hours ?? 0)

  switch (status) {
    case 'self':
      return zh ? '您' : 'You'
    case 'alert':
      return hours != null
        ? (zh ? `需要关注 · ${h}小时前有行为` : `Needs attention - ${h}h since activity`)
        : (zh ? '需要关注' : 'Needs attention')
    case 'active':
      return zh ? '近期活跃' : 'Recently active'
    case 'quiet':
      return hours != null
        ? (zh ? `安静 ${h} 小时` : `Quiet for ${h}h`)
        : (zh ? '暂无新活动' : 'Quiet')
    case 'silent':
      return hours != null
        ? (zh ? `${Math.max(1, Math.floor((hours ?? 24) / 24))}+ 天无行为` : `${Math.max(1, Math.floor((hours ?? 24) / 24))}+ day(s) no activity`)
        : (zh ? '长时间未活跃' : 'Inactive')
    case 'unknown':
      return zh ? '暂无行为记录' : 'No activity yet'
    case 'hidden':
    default:
      return zh ? '未公开' : 'Hidden'
  }
}
