/**
 * 被动签到的设置模型:三个数字,其余全部推导。
 *
 * 分层是这套设计的关键 —— 确认间隔不是采样率。设备按平台允许的节奏主动上报
 * (桌面 5 分钟、Android 15 分钟、iOS 60 分钟),确认间隔是**兜底值**:超过它
 * 还没收到上报,后台就敲门,让设备回查这段时间的历史。所以实际采集永远更密。
 *
 * 三个数字全部按**清醒时间**计,睡眠时段不计入。否则每个夜晚都会连续漏签。
 */

/**
 * 问1:多久之内必须确认到活动。
 *
 * 下限 90 分钟不是偏好,是 iOS 采集面自己声明的到达宽限 —— 低于它,一个完全
 * 健康的 iOS 采集器也会被判成失联。上限 360 分钟保证问3 的最低档里至少装得下
 * 两次确认。
 */
export const CHECKIN_MIN_MINUTES = 90
export const CHECKIN_MAX_MINUTES = 360
export const CHECKIN_STEP_MINUTES = 30
export const CHECKIN_DEFAULT_MINUTES = 120

/**
 * 问2:先通知本人、到通知群组之间的缓冲。
 *
 * 上限 90 分钟贴着急救文献里「长时间倒地」≥1 小时的风险门槛。下限 15 分钟是
 * 现实约束:再短,一个在开会或开车的人没有回应的机会。
 */
export const GRACE_MIN_MINUTES = 15
export const GRACE_MAX_MINUTES = 90
export const GRACE_STEP_MINUTES = 15
export const GRACE_DEFAULT_MINUTES = 45

/** 一次落空可能只是上报延迟,两次连续落空才排除得掉偶然。 */
export const MIN_CONSECUTIVE_MISSES = 2
export const MAX_CONSECUTIVE_MISSES = 8
export const MISSES_DEFAULT = 2

/** 再长,通知已经失去救援意义。 */
export const OUTREACH_MAX_MINUTES = 48 * 60

/**
 * 真人实测:四个随身用机的人,17 天,扣掉睡眠后最长的一次安静是 7.1 小时。
 * 设在这个值以下,日常生活会被判成异常 —— 这是警示,不是禁止。
 */
export const OBSERVED_MAX_AWAKE_QUIET_MINUTES = 426

function clamp(value: number, min: number, max: number, step: number): number {
  return Math.min(max, Math.max(min, Math.round(value / step) * step))
}

export function clampCheckin(minutes: number): number {
  return clamp(minutes, CHECKIN_MIN_MINUTES, CHECKIN_MAX_MINUTES, CHECKIN_STEP_MINUTES)
}

export function clampGrace(minutes: number): number {
  return clamp(minutes, GRACE_MIN_MINUTES, GRACE_MAX_MINUTES, GRACE_STEP_MINUTES)
}

/**
 * 问3 的合法档位:`N × 问1 + 问2`。
 *
 * 滑条只停在这些值上,因为界面显示的「连续 N 次漏签」必须和引擎实际做的一致。
 * 一个 314 分钟的设置算不出整数次漏签,那就不该存在。
 */
export function outreachLadder(checkinMinutes: number, graceMinutes: number): number[] {
  const rungs: number[] = []
  for (let n = MIN_CONSECUTIVE_MISSES; ; n += 1) {
    const value = n * checkinMinutes + graceMinutes
    if (value > OUTREACH_MAX_MINUTES) break
    rungs.push(value)
  }
  return rungs
}

export function snapOutreach(requested: number, checkinMinutes: number, graceMinutes: number): number {
  const rungs = outreachLadder(checkinMinutes, graceMinutes)
  return rungs.reduce(
    (best, rung) => (Math.abs(rung - requested) < Math.abs(best - requested) ? rung : best),
    rungs[0],
  )
}

/** 反推连续几次漏签。只用于显示,不让用户填。 */
export function consecutiveMissesFor(
  outreachMinutes: number,
  checkinMinutes: number,
  graceMinutes: number,
): number {
  return Math.max(
    MIN_CONSECUTIVE_MISSES,
    Math.round((outreachMinutes - graceMinutes) / checkinMinutes),
  )
}

/**
 * 失联总时长 = 连续 N 次没签到 + 留给本人回应的时间。
 *
 * 这个数不单独存储,它是另外两项加漏签次数算出来的。界面把它放在最上面,因为
 * 它是唯一一个「多久之后别人会被惊动」的答案。
 */
export function outreachTotal(misses: number, checkinMinutes: number, graceMinutes: number): number {
  return misses * checkinMinutes + graceMinutes
}

export function clampMisses(misses: number): number {
  return Math.min(MAX_CONSECUTIVE_MISSES, Math.max(MIN_CONSECUTIVE_MISSES, Math.round(misses)))
}

/** 「4 小时 45 分钟」比「285 分钟」和「4.75 小时」都好读。 */
export function formatDuration(minutes: number, zh: boolean): string {
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return zh ? `${m} 分钟` : `${m} min`
  if (m === 0) return zh ? `${h} 小时` : `${h} h`
  return zh ? `${h} 小时 ${m} 分钟` : `${h} h ${m} min`
}

export function isSensitiveOutreach(outreachMinutes: number, recommendedMinutes: number): boolean {
  return outreachMinutes < recommendedMinutes
}

/**
 * 建议时长的来源分两种,措辞必须跟着来源变。
 *
 * 攒够这个账号自己的证据之前,我们只能拿群体观测说话 —— 那时说「根据您的数据」
 * 是不诚实的,因为那还不是他的数据。
 */
export type RecommendationSource = 'account' | 'platform'

/**
 * 群体兜底值。真人实测清醒时最长安静 7.1 小时,取整到 10 小时留约 40% 余量。
 * 有了账号自己的 `threshold_minutes` 之后,用它替换。
 */
export const PLATFORM_RECOMMENDED_MINUTES = 10 * 60

/**
 * 用账号自己的数据说话之前,先得真的有账号自己的数据。
 *
 * 三十天是服务端那个估计器自己的回看窗口。不足三十天时它照样算得出一个数字,
 * 但那个数字描述的是一段比它自称的更短的生活:一个刚装上 App、这几天正好在休假
 * 的人会拿到一个假的紧凑建议,然后照着它把时长调短。说「根据您的数据」而那还不是
 * 他的数据,比不给建议更糟。
 */
export const ACCOUNT_RECOMMENDATION_MIN_EVIDENCE_DAYS = 30

export interface AccountRecommendationEvidence {
  referenceMinutes: number
  evidenceDays: number
  confidence: 'insufficient' | 'low' | 'medium' | 'high'
}

export function recommendationFor(
  account: AccountRecommendationEvidence | null,
): { minutes: number; source: RecommendationSource } {
  const earned =
    account !== null
    && account.referenceMinutes > 0
    && account.evidenceDays >= ACCOUNT_RECOMMENDATION_MIN_EVIDENCE_DAYS
    && account.confidence !== 'insufficient'
  return earned
    ? { minutes: account.referenceMinutes, source: 'account' }
    : { minutes: PLATFORM_RECOMMENDED_MINUTES, source: 'platform' }
}

/** 阈值的单位是清醒时间。标签必须把这件事说出来,否则用户会按钟表时间理解。 */
export function formatAwakeHours(minutes: number, zh: boolean): string {
  if (minutes < 60) return zh ? `${minutes} 分钟清醒` : `${minutes} min awake`
  const hours = minutes / 60
  const text = Number.isInteger(hours) ? String(hours) : hours.toFixed(1)
  return zh ? `${text} 小时清醒` : `${text} h awake`
}

export function formatGrace(minutes: number, zh: boolean): string {
  if (minutes < 60) return zh ? `${minutes} 分钟` : `${minutes} min`
  const hours = minutes / 60
  const text = Number.isInteger(hours) ? String(hours) : hours.toFixed(1)
  return zh ? `${text} 小时` : `${text} h`
}
