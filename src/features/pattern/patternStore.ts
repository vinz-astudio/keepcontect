// 解锁手势仅作本机"报平安"凭据：存哈希（非明文），完全本地。
// KCA-04 / ISO-01：手势哈希是紧急信息加密密钥的派生源，必须按账户隔离。
// 键名以 uid 命名空间：kc.patternHash.<uid>。历史遗留的全局 kc.patternHash
// 属"无主"——绝不跨账户被收养（否则用户 B 会继承用户 A 的哈希/密钥）。

const LEGACY_KEY = 'kc.patternHash'
const OPEN_ALERT_KEY = 'kc.openAlert'

/** 当前账户的手势哈希键 */
export function patternKey(uid: string): string {
  return `${LEGACY_KEY}.${uid}`
}

async function hashSeq(seq: number[]): Promise<string> {
  const data = new TextEncoder().encode('kc:' + seq.join('-'))
  const buf = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/** 读取当前账户的手势哈希（仅本命名空间，绝不回退到遗留全局键） */
export function getPatternHash(uid: string): string | null {
  return localStorage.getItem(patternKey(uid))
}

export function hasPattern(uid: string): boolean {
  return !!getPatternHash(uid)
}

export async function setPattern(uid: string, seq: number[]): Promise<string> {
  const hash = await hashSeq(seq)
  localStorage.setItem(patternKey(uid), hash)
  return hash
}

export async function verifyPattern(uid: string, seq: number[]): Promise<boolean> {
  const stored = getPatternHash(uid)
  if (!stored) return false
  return stored === (await hashSeq(seq))
}

export function clearPattern(uid: string): void {
  localStorage.removeItem(patternKey(uid))
}

export interface PatternAdoptionInput {
  /** 本账户命名空间里已有的哈希（若有） */
  scopedHash: string | null
  /** 遗留全局键的值（无主，可能属于上一个账户） */
  legacyHash: string | null
  /** 服务器为本账户存的哈希（本账户的权威真相） */
  serverHash: string | null
}

export interface PatternAdoptionResult {
  /** 需要写入本账户命名空间的哈希；null=无需写入 */
  hashToStore: string | null
  /** 是否清除遗留全局键 */
  clearLegacy: boolean
  /** 本账户是否尚未登记（需引导设置手势） */
  needsSetup: boolean
}

/**
 * 迁移/收养决策（纯函数，安全边界所在）：
 * - 采用的哈希只可能来自「已在本命名空间」或「服务器为本账户存的」——两者都属本账户。
 * - 遗留全局键永远不作为采用来源，只会被清除；因此用户 B 绝不会继承用户 A 的遗留哈希。
 * - 遗留键仅本账户无 server/scoped 哈希时无法安全归属 → 强制重新设置（重画同样手势即恢复）。
 */
export function resolvePatternAdoption(input: PatternAdoptionInput): PatternAdoptionResult {
  const { scopedHash, legacyHash, serverHash } = input
  const clearLegacy = !!legacyHash

  if (scopedHash) {
    return { hashToStore: null, clearLegacy, needsSetup: false }
  }
  if (serverHash) {
    return { hashToStore: serverHash, clearLegacy, needsSetup: false }
  }
  // 无本账户 scoped/server 哈希：遗留键无法安全归属，绝不采用。
  return { hashToStore: null, clearLegacy, needsSetup: true }
}

/**
 * 登出时清除本机安全状态：遗留全局哈希 + 所有 uid 命名空间手势哈希 + openAlert。
 * 保留非敏感 UI 偏好（kc.lang、kc.pushPrompt.dismissed 等）。
 */
export function purgeLocalSafetyState(): void {
  const toRemove: string[] = []
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i)
    if (!k) continue
    if (k === LEGACY_KEY || k.startsWith(LEGACY_KEY + '.') || k === OPEN_ALERT_KEY) {
      toRemove.push(k)
    }
  }
  for (const k of toRemove) localStorage.removeItem(k)
}
