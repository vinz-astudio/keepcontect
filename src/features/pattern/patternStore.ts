// 解锁手势仅作本机"报平安"凭据：存哈希（非明文），完全本地。
// KCA-04 / ISO-01：手势哈希是紧急信息加密密钥的派生源，必须按账户隔离。
// 键名以 uid 命名空间：kc.patternHash.<uid>。历史遗留的全局 kc.patternHash
// 属"无主"——绝不跨账户被收养（否则用户 B 会继承用户 A 的哈希/密钥）。

const LEGACY_KEY = 'kc.patternHash'
const OPEN_ALERT_KEY = 'kc.openAlert'
const PASSCODE_PREFIX = 'kc.passcodeHash'

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

/**
 * 手势和数字密码是两个独立的凭据,各自都能解锁。
 *
 * 用户可以只设一个,也可以两个都设,解锁时自己挑顺手的那个。所以它们各占一个槽,
 * 设了其中一个不会让另一个失效。
 *
 * 有一处不对称必须记住:个人紧急资料的加密密钥仍然从**手势**哈希派生
 * (`emergencyApi.deriveKeyFromPassword`)。只设数字密码的账号没有这个派生源。
 * 所以密码可以解锁,但不能替手势解开已经加密的个人紧急资料 —— 要改掉这个不对称,
 * 需要把密钥改成由凭据「解开」而不是「充当」,那是一次要重新加密存量数据的迁移。
 */
export const PASSCODE_MIN_LENGTH = 4
export const PASSCODE_MAX_LENGTH = 8

export function passcodeKey(uid: string): string {
  return `${PASSCODE_PREFIX}.${uid}`
}

/**
 * 数字密码和手势用不同的哈希域。
 *
 * 否则密码「1234」和手势 1-2-3-4 会算出同一个哈希,两个本该独立的凭据在存储层
 * 变成同一个值。
 */
async function hashPasscode(digits: string): Promise<string> {
  const data = new TextEncoder().encode('kc:pin:' + digits)
  const buf = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export function isPasscodeAcceptable(digits: string): boolean {
  if (!/^[0-9]+$/.test(digits)) return false
  return digits.length >= PASSCODE_MIN_LENGTH && digits.length <= PASSCODE_MAX_LENGTH
}

export function getPasscodeHash(uid: string): string | null {
  return localStorage.getItem(passcodeKey(uid))
}

export function hasPasscode(uid: string): boolean {
  return !!getPasscodeHash(uid)
}

export async function setPasscode(uid: string, digits: string): Promise<string> {
  if (!isPasscodeAcceptable(digits)) throw new Error('passcode rejected')
  const hash = await hashPasscode(digits)
  localStorage.setItem(passcodeKey(uid), hash)
  return hash
}

export async function verifyPasscode(uid: string, digits: string): Promise<boolean> {
  const stored = getPasscodeHash(uid)
  if (!stored) return false
  return stored === (await hashPasscode(digits))
}

export function clearPasscode(uid: string): void {
  localStorage.removeItem(passcodeKey(uid))
}

/** 这个账号设了哪些解锁方式。解锁界面据此决定给不给切换。 */
export function availableUnlockMethods(uid: string): { pattern: boolean; passcode: boolean } {
  return { pattern: hasPattern(uid), passcode: hasPasscode(uid) }
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
    if (k === LEGACY_KEY || k.startsWith(LEGACY_KEY + '.')
      || k.startsWith(PASSCODE_PREFIX + '.') || k === OPEN_ALERT_KEY) {
      toRemove.push(k)
    }
  }
  for (const k of toRemove) localStorage.removeItem(k)
}
