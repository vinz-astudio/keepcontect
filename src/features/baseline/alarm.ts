// 应用内告警声：当 App 处于前台且有真告警时，主动发声 + 震动，
// 不依赖系统通知设置（系统推送的声音由 iOS/Android 设备设置决定，Web 无法强制）。
// 用 Web Audio 合成"双哔"循环，无需音频资源。

let ctx: AudioContext | null = null
let timer: number | null = null
let primed = false

function makeCtx(): AudioContext | null {
  if (ctx) return ctx
  try {
    const Ctor =
      window.AudioContext ||
      (window as unknown as { webkitAudioContext?: typeof AudioContext })
        .webkitAudioContext
    if (!Ctor) return null
    ctx = new Ctor()
  } catch {
    return null
  }
  return ctx
}

function beep() {
  const c = ctx
  if (!c) return
  const burst = (offset: number) => {
    const o = c.createOscillator()
    const g = c.createGain()
    o.type = 'sine'
    o.frequency.value = 880
    const t0 = c.currentTime + offset
    g.gain.setValueAtTime(0.0001, t0)
    g.gain.exponentialRampToValueAtTime(0.8, t0 + 0.02) // 响一些：安全告警要醒目
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.18)
    o.connect(g)
    g.connect(c.destination)
    o.start(t0)
    o.stop(t0 + 0.2)
  }
  burst(0)
  burst(0.28) // 双哔，更像"警报"
}

/**
 * 让浏览器在首个用户手势时解锁音频（iOS 自动播放限制）。
 * 在 App 启动时调用一次即可。
 */
export function primeAlarm() {
  if (primed) return
  primed = true
  const unlock = () => {
    const c = makeCtx()
    if (c && c.state === 'suspended') void c.resume()
    window.removeEventListener('pointerdown', unlock)
    window.removeEventListener('keydown', unlock)
  }
  window.addEventListener('pointerdown', unlock, { once: true })
  window.addEventListener('keydown', unlock, { once: true })
}

export function startAlarm() {
  if (timer != null) return
  const c = makeCtx()
  if (!c) return
  void c.resume() // 若此刻有手势上下文则立即恢复
  beep()
  timer = window.setInterval(beep, 1400)
  try {
    navigator.vibrate?.([400, 200, 400]) // Android 震动；iOS 忽略
  } catch {
    /* 不支持则忽略 */
  }
}

export function stopAlarm() {
  if (timer != null) {
    window.clearInterval(timer)
    timer = null
  }
  try {
    navigator.vibrate?.(0)
  } catch {
    /* 忽略 */
  }
}
