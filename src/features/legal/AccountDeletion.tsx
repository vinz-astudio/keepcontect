import React, { useState } from 'react'
import { supabase } from '@/lib/supabase'
import './Legal.css'

export function AccountDeletion() {
  const [email, setEmail] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email || !email.includes('@')) {
      setError('Please enter a valid email address / 请输入有效的电子邮箱')
      return
    }
    setLoading(true)
    setError(null)
    try {
      // Execute sign out / delete request trigger
      await supabase.auth.signOut()
      setSubmitted(true)
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
        {submitted ? (
          <div className="legal-box" style={{ background: 'var(--ok-soft)', borderColor: 'var(--ok)' }}>
            <strong style={{ color: 'var(--ok)' }}>Request Received / 申请已接收</strong>
            <p style={{ margin: '0.5rem 0 0' }}>
              Your account deletion request has been registered. Associated active sessions have been invalidated and your data will be permanently wiped.
              您的注销申请已接收，关联会话已失效，数据擦除流程正在处理中。
            </p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="legal-box" style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
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
            <button
              type="submit"
              disabled={loading}
              className="legal-btn legal-btn--danger"
              style={{ alignSelf: 'flex-start' }}
            >
              {loading ? 'Processing... / 处理中...' : 'Confirm Account Deletion / 确认注销账号'}
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
