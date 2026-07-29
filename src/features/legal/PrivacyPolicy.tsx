import React from 'react'
import './Legal.css'

export function PrivacyPolicy() {
  return (
    <div className="legal-page">
      <header className="legal-header">
        <div className="legal-brand">Keep Contact</div>
        <h1 className="legal-title">Privacy Policy / 隐私政策</h1>
        <div className="legal-date">Last updated / 最终更新时间: July 29, 2026</div>
      </header>

      <section className="legal-section">
        <h2>1. Purpose & Application Overview / 应用概述与用途</h2>
        <p>
          Keep Contact is a personal safety and liveness monitoring application designed primarily for lone dwellers, elderly family members, and individuals living alone. The app provides automated, passive safety check-ins to alert designated emergency guardians if a user becomes uncommunicative or experiences a sudden emergency.
        </p>
        <p>
          Keep Contact 是一款专为独居群体、独居长者及有安全监护需求的人群设计的无感安全守护应用。应用通过对设备基本活跃状态的被动感应，在用户长时间无任何操作或发生突发危险时，自动向其指定的紧急联系人发出安全预警。
        </p>
      </section>

      <section className="legal-section">
        <h2>2. Information We Collect / 我们收集的信息</h2>
        <p>To deliver automated liveness checks, Keep Contact collects the following limited data types / 为提供被动安全守护功能，Keep Contact 仅收集以下有限信息：</p>
        <ul>
          <li>
            <strong>Account Data / 账号信息:</strong> Email address and authentication tokens used exclusively for securing account access and sending guardian notifications.
          </li>
          <li>
            <strong>Device Activity Signals / 设备活跃信号:</strong> Passive timestamp events (such as charger plug/unplug, screen wake/unlock, and non-sensitive app usage timestamps) to detect whether the user is actively using their device.
          </li>
          <li>
            <strong>Emergency Contacts / 紧急联系人:</strong> Email addresses or contact links of designated guardians authorized by the user to receive safety notifications.
          </li>
        </ul>
        <div className="legal-box">
          <strong>Privacy Promise / 隐私承诺:</strong> We DO NOT collect, store, or transmit your screen contents, private messages, browsed websites, photos, microphone audio, or physical location histories.
          我们绝不收集、存储或传输您的屏幕内容、聊天记录、浏览历史、相册照片、麦克风录音或后台物理定位轨迹。
        </div>
      </section>

      <section className="legal-section">
        <h2>3. Use of Background Services / 后台服务与权限使用说明</h2>
        <p>
          Keep Contact runs a Foreground Service declared under Google Play's <code>specialUse</code> category (Emergency and personal safety monitoring). This service ensures that passive screen-on and charger pings can be captured reliably 24/7 without being killed by Android battery optimization.
        </p>
        <p>
          Keep Contact 声明了符合 Google Play 规范的 <code>specialUse</code> 特殊用途前台服务（紧急与个人安全监护），确保在后台 24/7 稳定捕捉亮屏与电源状态，防止因系统省电策略导致被动防护中断。
        </p>
      </section>

      <section className="legal-section">
        <h2>4. Data Sharing & Security / 数据共享与安全保障</h2>
        <p>
          We do not sell, rent, or trade user personal data to third parties, advertisers, or data brokers under any circumstances. All network communications are encrypted via TLS/HTTPS, and data at rest is stored in secure PostgreSQL database infrastructure with Row Level Security (RLS) enforcement.
        </p>
        <p>
          在任何情况下，我们都不会向第三方、广告商或数据经纪商出售、出租或交易用户的个人数据。所有传输过程均经由 HTTPS/TLS 加密，后台存储数据受到严格的行级安全策略（RLS）保护。
        </p>
      </section>

      <section className="legal-section">
        <h2>5. Data Deletion & Account Erasure / 数据删除与账号注销权益</h2>
        <p>
          Users maintain full control over their data. You may request immediate deletion of your account and all associated passive signal records at any time.
        </p>
        <p>
          用户对其个人数据享有完全的控制权。您有权随时注销账号并要求彻底擦除所有关联的被动信号记录。
        </p>
        <div style={{ marginTop: '1rem' }}>
          <a href="/delete-account" className="legal-btn legal-btn--danger">
            Request Account & Data Deletion / 申请注销账号与删除数据
          </a>
        </div>
      </section>

      <footer className="legal-footer">
        <div>© 2026 Keep Contact. All rights reserved.</div>
        <nav className="legal-nav">
          <a href="/">App Home / 返回主页</a>
          <a href="/delete-account">Delete Account / 账号注销</a>
        </nav>
      </footer>
    </div>
  )
}
