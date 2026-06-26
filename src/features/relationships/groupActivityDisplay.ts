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
      return zh ? '你' : 'You'
    case 'alert':
      return zh ? `需要关注 · ${h}小时前有行为` : `Needs attention - ${h}h since activity`
    case 'active':
      return zh ? '近期有行为' : 'Recently active'
    case 'quiet':
      return zh ? `安静 ${h} 小时` : `Quiet for ${h}h`
    case 'silent':
      return zh
        ? `${Math.max(1, Math.floor((hours ?? 24) / 24))}+ 天无行为`
        : `${Math.max(1, Math.floor((hours ?? 24) / 24))}+ day(s) no activity`
    case 'unknown':
      return zh ? '暂无行为记录' : 'No activity yet'
    case 'hidden':
    default:
      return zh ? '未公开' : 'Hidden'
  }
}
