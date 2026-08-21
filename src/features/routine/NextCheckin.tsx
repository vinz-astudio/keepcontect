
/**
 * 滚动截止点,锚在最新一次告活证据的发生时间(`observed_at`),不是上报时间。
 *
 * 这是本人唯一能一眼看懂「被动签到到底灵不灵」的地方:每次被检测到还在,数字
 * 跳回满格。锁死的时刻做不到这件事,因为它不管您做了什么都不动。
 *
 * 服务器算的那一份优先。本地这份少一样东西 —— 它不知道睡眠时段,而引擎判断时
 * 睡眠不计入阈值。凌晨三点本地会算出「现在」,引擎却还早得很。两个数字不一致
 * 时,以引擎会照着做的那个为准。
 */
export function nextCheckinRemainingMinutes(
  lastActivityAt: string | null,
  thresholdMinutes: number,
  now: Date = new Date(),
  serverDeadlineAt: string | null = null,
): number | null {
  const deadline = serverDeadline(serverDeadlineAt) ?? localDeadline(lastActivityAt, thresholdMinutes)
  if (deadline === null) return null
  return Math.round((deadline - now.getTime()) / 60_000)
}

/** 断网或旧后端时的兜底:本地按钟表时间推。 */
function localDeadline(lastActivityAt: string | null, thresholdMinutes: number): number | null {
  if (!lastActivityAt) return null
  const last = Date.parse(lastActivityAt)
  if (Number.isNaN(last)) return null
  return last + thresholdMinutes * 60_000
}

function serverDeadline(serverDeadlineAt: string | null): number | null {
  if (!serverDeadlineAt) return null
  const at = Date.parse(serverDeadlineAt)
  return Number.isNaN(at) ? null : at
}

/** 粗粒度。显示秒会把一个安心的界面变成倒数的末日钟。 */
export function formatRemaining(minutes: number, zh: boolean): string {
  if (minutes <= 0) return zh ? '现在' : 'now'
  if (minutes < 90) return zh ? `约 ${minutes} 分钟` : `about ${minutes} min`
  const hours = Math.round(minutes / 60)
  return zh ? `约 ${hours} 小时` : `about ${hours} h`
}
