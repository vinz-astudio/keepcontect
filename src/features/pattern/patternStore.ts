// 解锁手势仅作本机"报平安"凭据：存哈希（非明文），完全本地。

const KEY = 'kc.patternHash'

async function hashSeq(seq: number[]): Promise<string> {
  const data = new TextEncoder().encode('kc:' + seq.join('-'))
  const buf = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export function hasPattern(): boolean {
  return !!localStorage.getItem(KEY)
}

export async function setPattern(seq: number[]): Promise<void> {
  localStorage.setItem(KEY, await hashSeq(seq))
}

export async function verifyPattern(seq: number[]): Promise<boolean> {
  const stored = localStorage.getItem(KEY)
  if (!stored) return false
  return stored === (await hashSeq(seq))
}

export function clearPattern(): void {
  localStorage.removeItem(KEY)
}
