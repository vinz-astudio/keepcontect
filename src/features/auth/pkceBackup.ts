// PKCE verifier 备份/恢复。
// 背景：iOS 主屏 PWA 在 OAuth 授权层交还的瞬间可能掐死首次兑换请求（TypeError），
// 而 gotrue 无论成败都会删除存储中的 code verifier——首败即永败。
// 对策：发起跳转前备份 verifier cookie；落地重试前若 verifier 缺失则恢复后再兑换。

const BACKUP_KEY = 'kc.pkce_backup'
const MAX_AGE_MS = 10 * 60_000

interface Backup {
  at: number
  cookies: Array<{ name: string; value: string }>
}

function verifierCookies(): Array<{ name: string; value: string }> {
  try {
    return document.cookie
      .split(';')
      .map((c) => c.trim())
      .filter((c) => /-code-verifier(\.\d+)?=/.test(c))
      .map((c) => {
        const i = c.indexOf('=')
        return { name: c.slice(0, i), value: c.slice(i + 1) }
      })
  } catch {
    return []
  }
}

/** 发起 OAuth 跳转前调用：备份当前 verifier cookie */
export function backupVerifier(): boolean {
  const cookies = verifierCookies()
  if (cookies.length === 0) return false
  try {
    const b: Backup = { at: Date.now(), cookies }
    localStorage.setItem(BACKUP_KEY, JSON.stringify(b))
    return true
  } catch {
    return false
  }
}

/** verifier 已被消费删除时调用：把备份恢复回 cookie。返回是否恢复了。 */
export function restoreVerifier(): boolean {
  try {
    const raw = localStorage.getItem(BACKUP_KEY)
    if (!raw) return false
    const b = JSON.parse(raw) as Backup
    if (Date.now() - b.at > MAX_AGE_MS) return false
    const secure = location.protocol === 'https:' ? '; secure' : ''
    for (const { name, value } of b.cookies) {
      document.cookie = `${name}=${value}; path=/; max-age=600; samesite=lax${secure}`
    }
    return b.cookies.length > 0
  } catch {
    return false
  }
}

export function hasVerifierInStorage(): boolean {
  return verifierCookies().length > 0
}

export function clearVerifierBackup(): void {
  try {
    localStorage.removeItem(BACKUP_KEY)
  } catch { /* ignore */ }
}
