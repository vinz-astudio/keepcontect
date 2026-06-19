// 邀请链接：生成可分享的 URL、解析进入时的邀请参数、登录前暂存。
// 链接形如 https://app.example.com/?invite=group.abc123（query 参数，SPA 无需服务端路由）

import { translate } from '@/lib/i18n'

export type InviteKind = 'group' | 'community' | 'guardian'

export interface Invite {
  kind: InviteKind
  code: string
}

const PENDING_KEY = 'kc.pendingInvite'

export function buildInviteUrl(kind: InviteKind, code: string): string {
  return `${location.origin}${location.pathname}?invite=${kind}.${encodeURIComponent(code)}`
}

/** 从当前 URL 解析邀请参数；解析后调用方应清理地址栏 */
export function parseInviteFromUrl(): Invite | null {
  const raw = new URLSearchParams(location.search).get('invite')
  if (!raw) return null
  const dot = raw.indexOf('.')
  if (dot <= 0) return null
  const kind = raw.slice(0, dot)
  const code = decodeURIComponent(raw.slice(dot + 1))
  if (kind !== 'group' && kind !== 'community' && kind !== 'guardian') return null
  if (!code) return null
  return { kind, code }
}

export function clearInviteFromUrl(): void {
  const url = new URL(location.href)
  url.searchParams.delete('invite')
  history.replaceState(null, '', url.toString())
}

export function savePendingInvite(inv: Invite): void {
  localStorage.setItem(PENDING_KEY, JSON.stringify(inv))
}

export function takePendingInvite(): Invite | null {
  const raw = localStorage.getItem(PENDING_KEY)
  if (!raw) return null
  localStorage.removeItem(PENDING_KEY)
  try {
    const v = JSON.parse(raw) as Invite
    return v.kind && v.code ? v : null
  } catch {
    return null
  }
}

export function peekPendingInvite(): Invite | null {
  const raw = localStorage.getItem(PENDING_KEY)
  if (!raw) return null
  try {
    const v = JSON.parse(raw) as Invite
    return v.kind && v.code ? v : null
  } catch {
    return null
  }
}

/** 解析用户粘贴的文本：完整邀请链接或 `kind.code` 形式 */
export function parseInviteText(text: string): Invite | null {
  const t = text.trim()
  if (!t) return null
  try {
    const url = new URL(t.match(/https?:\/\/\S+/)?.[0] ?? t)
    const raw = url.searchParams.get('invite')
    if (raw) {
      const dot = raw.indexOf('.')
      const kind = raw.slice(0, dot)
      const code = decodeURIComponent(raw.slice(dot + 1))
      if ((kind === 'group' || kind === 'community' || kind === 'guardian') && code)
        return { kind, code }
    }
  } catch {
    // 非 URL：尝试 kind.code
    const dot = t.indexOf('.')
    if (dot > 0) {
      const kind = t.slice(0, dot)
      const code = t.slice(dot + 1)
      if ((kind === 'group' || kind === 'community' || kind === 'guardian') && code)
        return { kind, code }
    }
  }
  return null
}

const SHARE_TEXT: Record<InviteKind, (name: string) => string> = {
  group: (n) => translate('share.group', { name: n }),
  community: (n) => translate('share.community', { name: n }),
  guardian: (n) => translate('share.guardian', { name: n }),
}

export interface ShareResult {
  status: 'shared' | 'copied' | 'manual'
  url: string
}

/**
 * 分享邀请：①唤起系统分享面板（手机上即微信/WhatsApp/LINE 等）
 * → ②回退复制到剪贴板 → ③仍失败则返回 manual，由界面直接展示链接。
 * 永不抛错。
 */
export async function shareInvite(
  kind: InviteKind,
  code: string,
  name: string,
): Promise<ShareResult> {
  const url = buildInviteUrl(kind, code)
  const text = SHARE_TEXT[kind](name)
  if (navigator.share) {
    try {
      await navigator.share({ title: 'Keep Contact 邀请', text, url })
      return { status: 'shared', url }
    } catch (e) {
      // 用户取消分享不算失败；其余情况继续回退
      if ((e as DOMException)?.name === 'AbortError') return { status: 'shared', url }
    }
  }
  try {
    await navigator.clipboard.writeText(`${text} ${url}`)
    return { status: 'copied', url }
  } catch {
    return { status: 'manual', url }
  }
}
