import React, { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { deleteMyAccount } from '@/features/profile/profileApi'
import './Legal.css'

export function AccountDeletion() {
  const [email, setEmail] = useState('')
  const [confirmPhrase, setConfirmPhrase] = useState('')
  const [sessionUser, setSessionUser] = useState<string | null>(null)
  const [submittedType, setSubmittedType] = useState<'deleted' | 'sent_link' | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session?.user) {
        setSessionUser(session.user.email ?? session.user.id)
        if (session.user.email) setEmail(session.user.email)
      }
    })
  }, [])

  const isLoggedInAsTarget = Boolean(sessionUser && sessionUser === email)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || !email.includes('@')) {
      setError('Please enter a valid email address / 请输入有效的电子邮箱')
      return
    }
    if (isLoggedInAsTarget && confirmPhrase !== 'DELETE') {
      setError('Please type exact "DELETE" to confirm permanent deletion / 请输入完全匹配的 "DELETE" 以确认注销')
      return
    }



    setLoading(true)
    setError(null)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const isFreshLoggedInAsTarget = Boolean(session?.user && session.user.email === email)
      if (isFreshLoggedInAsTarget) {
        if (confirmPhrase !== 'DELETE') {
          setError('Please type exact "DELETE" to confirm permanent deletion / 请输入完全匹配的 "DELETE" 以确认注销')
          setLoading(false)
          return
        }
        await deleteMyAccount()
        setSubmittedType('deleted')
      } else {

        // If not logged in as this email, send sign-in link with shouldCreateUser: false to prove ownership
        const { error: otpErr } = await supabase.auth.signInWithOtp({
          email,
          options: {
            shouldCreateUser: false,
            emailRedirectTo: window.location.href,
          },
        })
        if (otpErr) throw otpErr
        setSubmittedType('sent_link')
      }
    } catch (err: any) {
      setError(err?.message || 'Failed to submit request / 提交失败')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="legal-page">
      <header className="legal-header">
        <div className="legal-brand">Keep Contact</div>
        <h1 className="legal-title">Account & Data Deletion Request / 账号与数据注销申请</h1>
        <div className="legal-date">Google Play Store Data Erasure Portal</div>
      </header>

      <section className="legal-section">
        <p>
          In compliance with Google Play Store User Data policies, Keep Contact provides a direct method for users to request the permanent deletion of their account, emergency contacts, and all historical passive safety signal logs.
        </p>
        <p>
          根据 Google Play 开发者用户数据政策要求，Keep Contact 为用户提供直接注销账号并永久删除紧急联系人及所有历史被动安全信号日志的服务。
        </p>
      </section>

      <section className="legal-section">
        <h2>What Data Will Be Deleted / 被删除的数据范围</h2>
        <ul>
          <li><strong>Authentication Account & Profile:</strong> User credentials, display name, and auth records.</li>
          <li><strong>Passive Safety Pings & Signals:</strong> All timestamps of charger connections, screen wakes, and usage events.</li>
          <li><strong>Guardian Links & Circles:</strong> Relationships and active emergency notification routing.</li>
        </ul>
      </section>

      <section className="legal-section">
        <h2>Submit Deletion Request / 提交注销申请</h2>
        {submittedType === 'deleted' ? (
          <div className="legal-box" style={{ background: 'var(--ok-soft)', borderColor: 'var(--ok)' }}>
            <strong style={{ color: 'var(--ok)' }}>Account Deleted / 账号已永久注销</strong>
            <p style={{ margin: '0.5rem 0 0' }}>
              Your account and all associated emergency contacts and passive signal data have been permanently wiped.
              您的账号及所有关联紧急联系人与被动信号数据已彻底销毁。
            </p>
          </div>
        ) : submittedType === 'sent_link' ? (
          <div className="legal-box" style={{ background: 'var(--accent-soft)', borderColor: 'var(--accent)' }}>
            <strong style={{ color: 'var(--fg)' }}>Verification Email Sent / 验证邮件已发送</strong>
            <p style={{ margin: '0.5rem 0 0' }}>
              A confirmation sign-in link has been sent to {email}. Please click the link in your email to authenticate and confirm permanent account deletion.
              确认邮件已发送至 {email}。请点击邮件中的链接登录以验证账号所有权并确认永久注销。
            </p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="legal-box" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            {sessionUser && (
              <div style={{ fontSize: '0.88rem', opacity: 0.8 }}>
                Logged in as / 当前登录身份: <strong>{sessionUser}</strong>
              </div>
            )}
            {error && <div style={{ color: 'var(--danger)', fontSize: '0.88rem' }}>{error}</div>}
            <label style={{ fontSize: '0.9rem', color: 'var(--fg)' }}>
              Registered Email Address / 注册电子邮箱:
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="your.email@example.com"
                required
                style={{
                  width: '100%',
                  padding: '0.65rem 0.8rem',
                  marginTop: '0.4rem',
                  fontSize: '0.95rem',
                  background: 'var(--bg)',
                  color: 'var(--fg)',
                  border: '1px solid var(--line)',
                  borderRadius: 'var(--r-sm)',
                  boxSizing: 'border-box'
                }}
              />
            </label>

            {isLoggedInAsTarget && (
              <label style={{ fontSize: '0.9rem', color: 'var(--fg)' }}>
                Type <strong>DELETE</strong> to confirm / 输入 <strong>DELETE</strong> 以确认永久注销:
                <input
                  type="text"
                  value={confirmPhrase}
                  onChange={(e) => setConfirmPhrase(e.target.value)}
                  placeholder="DELETE"
                  required
                  style={{
                    width: '100%',
                    padding: '0.65rem 0.8rem',
                    marginTop: '0.4rem',
                    fontSize: '0.95rem',
                    background: 'var(--bg)',
                    color: 'var(--fg)',
                    border: '1px solid var(--line)',
                    borderRadius: 'var(--r-sm)',
                    boxSizing: 'border-box'
                  }}
                />
              </label>
            )}

            <button
              type="submit"
              disabled={loading || (isLoggedInAsTarget && confirmPhrase !== 'DELETE')}
              className="legal-btn legal-btn--danger"
              style={{ alignSelf: 'flex-start' }}
            >


              {loading
                ? 'Processing... / 处理中...'
                : isLoggedInAsTarget
                  ? 'Permanently Delete Account / 永久注销此账号'
                  : 'Send Verification Link / 发送验证链接'}
            </button>
          </form>
        )}
      </section>



      <footer className="legal-footer">
        <div>© 2026 Keep Contact. All rights reserved.</div>
        <nav className="legal-nav">
          <a href="/">App Home / 返回主页</a>
          <a href="/privacy">Privacy Policy / 隐私政策</a>
        </nav>
      </footer>
    </div>
  )
}
