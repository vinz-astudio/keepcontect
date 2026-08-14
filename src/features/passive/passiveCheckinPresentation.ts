import { supabase } from '@/lib/supabase'

export type PassiveHealthState = 'ready' | 'limited' | 'off'
export interface PassiveDeviceHealth {
  bindingId: string
  device: string
  surfaceType: string
  state: 'ready' | 'limited'
  reason: string | null
  repairAction: string | null
  lastContactAt: string | null
}
export interface PassiveCollectorHealth {
  state: PassiveHealthState
  devices: PassiveDeviceHealth[]
  missCountingContinues: true
  evaluatedAt: string
  globalReason: string | null
  globalRepairAction: string | null
}

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : null
}

export function parsePassiveCollectorHealth(value: unknown): PassiveCollectorHealth {
  const raw = object(value)
  if (!raw || !['ready', 'limited', 'off'].includes(String(raw.state))
    || !Array.isArray(raw.devices) || raw.miss_counting_continues !== true
    || typeof raw.evaluated_at !== 'string' || Number.isNaN(Date.parse(raw.evaluated_at))) {
    throw new Error('Invalid passive collector health')
  }
  const devices = raw.devices.map((value): PassiveDeviceHealth => {
    const device = object(value)
    if (!device || typeof device.binding_id !== 'string' || typeof device.device !== 'string'
      || typeof device.surface_type !== 'string' || !['ready', 'limited'].includes(String(device.state))
      || (device.reason !== null && typeof device.reason !== 'string')
      || (device.repair_action !== null && typeof device.repair_action !== 'string')
      || (device.last_contact_at !== null && (typeof device.last_contact_at !== 'string' || Number.isNaN(Date.parse(device.last_contact_at))))) {
      throw new Error('Invalid passive collector health')
    }
    return {
      bindingId: device.binding_id, device: device.device, surfaceType: device.surface_type,
      state: device.state as PassiveDeviceHealth['state'], reason: device.reason,
      repairAction: device.repair_action, lastContactAt: device.last_contact_at,
    }
  })
  if (raw.state === 'off' && devices.length > 0) throw new Error('Invalid passive collector health')
  return {
    state: raw.state as PassiveHealthState, devices, missCountingContinues: true,
    evaluatedAt: raw.evaluated_at,
    globalReason: typeof raw.global_reason === 'string' ? raw.global_reason : null,
    globalRepairAction: typeof raw.global_repair_action === 'string' ? raw.global_repair_action : null,
  }
}

export function passiveHealthCopy(health: PassiveCollectorHealth, lang: 'zh' | 'en') {
  const label = lang === 'zh'
    ? ({ ready: '就绪', limited: '受限', off: '关闭' } as const)[health.state]
    : ({ ready: 'Ready', limited: 'Limited', off: 'Off' } as const)[health.state]
  const detail = health.state === 'ready'
    ? (lang === 'zh' ? '已绑定的采集器工作正常。' : 'Bound collectors are working normally.')
    : health.state === 'off'
      ? (lang === 'zh' ? '尚未绑定任何采集器。' : 'No collector is bound yet.')
      : health.globalReason
        ? (lang === 'zh'
            ? `KC 已启用全局安全停止：${health.globalReason}。已完成窗口不会被改写，漏签仍按事实记录，但不会新开被动告警。`
            : `KC's global safety stop is active: ${health.globalReason}. Completed windows stay unchanged and misses remain factual, but no new passive alert will open.`)
        : (lang === 'zh'
          ? '部分设备采集受限；漏签计数仍会继续，请按下方提示修复。'
          : 'Some device collection is limited. Miss counting continues; use the repair action below.')
  return { label, detail }
}

export async function getPassiveCollectorHealth(): Promise<PassiveCollectorHealth> {
  const { data, error } = await supabase.rpc('my_passive_collector_health')
  if (error) throw error
  return parsePassiveCollectorHealth(data)
}
