import './Legal.css'

export function PrivacyPolicy() {
  return (
    <div className="legal-page">
      <header className="legal-header">
        <div className="legal-brand">Keep Contact</div>
        <h1 className="legal-title">Privacy Policy / 隐私政策</h1>
        <div className="legal-date">Last updated / 最终更新时间: November 2, 2026</div>
      </header>

      <section className="legal-section">
        <h2>1. Purpose & Application Overview / 应用概述与用途</h2>
        <p>
          Keep Contact helps users and their chosen contacts stay connected through passive activity signals and deliberate safety check-ins. It is a best-effort service: background execution, delivery, and recovery are controlled by each operating system and device, so the app cannot guarantee continuous monitoring, immediate delivery, or emergency response.
        </p>
        <p>
          Keep Contact 通过被动活跃信号和用户主动进行的安全签到，帮助用户与其指定联系人保持联系。本服务仅尽力运行：后台执行、数据传递和恢复由操作系统及设备控制，因此不能保证持续监测、即时送达或紧急救援响应。
        </p>
      </section>

      <section className="legal-section">
        <h2>2. Information We Collect / 我们收集的信息</h2>
        <p>We collect the following categories when needed for the features you use / 根据您使用的功能，我们可能收集以下类别的信息：</p>
        <ul>
          <li><strong>Account Data / 账号信息:</strong> Account identifiers, email address, authentication and device-binding information needed to provide account access and notifications. / 为提供账号访问和通知所需的账号标识、电子邮箱、身份验证及设备绑定信息。</li>
          <li><strong>Linked Activity & Derived Evidence / 关联活跃信息与派生证据:</strong> Activity event timestamps and derived positive movement evidence used for check-in and coverage decisions. On iOS, raw Health or motion samples, step counts, floors, and activity values are evaluated on the device; only the resulting positive evidence and its interval are sent. We do not collect raw Health samples for this feature. / 用于签到和覆盖判断的活跃事件时间戳及派生的正向移动证据。在 iOS 上，原始健康或运动样本、步数、楼层数和活动值在设备本地评估；仅发送派生的正向证据及其时间区间。本功能不收集原始 Health 样本。</li>
          <li><strong>Device Diagnostics / 设备诊断信息:</strong> Diagnostics that may be uploaded with a sample, including battery level and power state, low-power mode, system uptime, whether other audio is playing, available disk or volume space, protected-data availability, and client/app version. These fields describe device conditions; the audio value does not identify what is playing. / 可能随样本上传的诊断信息，包括电池电量和电源状态、低电量模式、系统运行时间、是否有其他音频播放、可用磁盘或存储空间、受保护数据可用性以及客户端/应用版本。这些字段描述设备状态；音频字段不会识别正在播放的内容。</li>
          <li><strong>User-Entered Emergency Information / 用户填写的紧急信息:</strong> Emergency contact names and phone numbers, addresses, and medical information that you choose to enter. / 您主动填写的紧急联系人姓名和电话号码、地址及医疗信息。</li>
          <li><strong>Optional SOS Location / 可选 SOS 位置:</strong> If you separately choose to share your location for an SOS, we may receive the coordinates, accuracy, and update time needed for that SOS feature. / 如果您单独选择在 SOS 中分享位置，我们可能接收该功能所需的坐标、精度和更新时间。</li>
        </ul>
        <div className="legal-box">
          <strong>Content limits / 内容限制:</strong> We do not collect screen contents, private messages, browsing history, photos, microphone recordings, or any location history. Keep Contact does not use location in the background. Location is used only when you choose to share it in an SOS, while the app is in use.
          <br />
          我们不收集屏幕内容、私人消息、浏览历史、照片、麦克风录音或任何位置历史。Keep Contact 不在后台使用定位。仅当您在 SOS 中主动选择分享位置时，才会在使用 App 期间获取位置。
        </div>
      </section>

      <section className="legal-section">
        <h2>3. Background Services, Permissions & Service Limits / 后台服务、权限与服务限制</h2>
        <p>
          Keep Contact uses OS-approved background mechanisms where available. On Android, WorkManager and server wake-up paths are preferred; an Android foreground service using the Google Play <code>specialUse</code> category is a fallback for selected persistent-guard situations and requires the relevant user/device conditions. Google Play approval, battery restrictions, Doze, manufacturer settings, force-quit, network conditions, and other OS decisions can limit or stop any path. The foreground service is not a guarantee of 24/7 operation.
        </p>
        <p>
          Keep Contact 会在可用时使用操作系统允许的后台机制。在 Android 上，应用优先使用 WorkManager 和服务器唤醒路径；符合条件的持续守护场景可能使用 Google Play <code>specialUse</code> 类别的前台服务作为兜底，并受用户及设备条件限制。Google Play 审核、电池限制、Doze、厂商设置、用户强制退出、网络状况及其他系统决定都可能限制或停止这些路径。前台服务不代表保证 24/7 运行。
        </p>
        <p>
          On iOS, HealthKit background delivery and silent push notifications are best-effort mechanisms; iOS decides when, and whether, the app may run in the background. HealthKit permission is optional and only used for the derived positive movement evidence described above. Keep Contact does not request background location. Safety check-in notifications addressed to you, and emergency notifications, may be marked Time Sensitive so they can reach you during Focus; you can turn this off in iOS Settings.
        </p>
        <p>
          在 iOS 上，HealthKit 后台传递和静默推送都是尽力而为的机制；App 何时、能否在后台运行由 iOS 决定。HealthKit 权限为可选，仅用于上述派生的正向移动证据。Keep Contact 不申请后台定位。发给您本人的安全确认通知以及紧急通知可能被标记为"时效性通知"，以便在专注模式下也能送达；您可以在 iOS 设置中关闭。
        </p>
      </section>

      <section className="legal-section">
        <h2>4. Data Sharing & Security / 数据共享与安全保障</h2>
        <p>
          We do not sell, rent, or trade personal data to advertisers or data brokers. Data is transmitted using TLS/HTTPS and stored in PostgreSQL infrastructure with Row Level Security (RLS). Authorized Keep Contact server processing is required to provide account, check-in, notification, emergency, and diagnostic features. Some emergency fields may receive application-layer encryption when an encryption key is available; some fields may be stored without that additional layer. This does not mean that every field is end-to-end encrypted.
        </p>
        <p>
          我们不会将个人数据出售、出租或交易给广告商或数据经纪商。数据传输使用 TLS/HTTPS，并存储在启用行级安全策略（RLS）的 PostgreSQL 基础设施中。为提供账号、签到、通知、紧急信息和诊断功能，授权的 Keep Contact 服务器处理是必要的。部分紧急信息字段在有可用加密密钥时可能采用应用层加密；部分字段可能不具备这一额外加密层。这不表示所有字段都采用端到端加密。
        </p>
      </section>

      <section className="legal-section">
        <h2>5. Service Providers / 第三方服务商</h2>
        <p>
          Keep Contact uses the following service providers only to operate the features described above. They process data on our behalf, are bound by their own privacy and security commitments, and must provide the same or equal protection of user data as stated in this policy. We do not share data with advertisers or data brokers.
        </p>
        <ul>
          <li><strong>Supabase:</strong> database, authentication, and server functions that store and process the data in Section 2. / 数据库、身份验证和服务器函数，存储并处理第 2 节所述数据。</li>
          <li><strong>Google Firebase Cloud Messaging:</strong> delivers push notifications to Android and iOS. It receives your device push token. Most notifications are content-free wake-ups; on iOS, check-in notifications addressed to you carry their text so the system can display them. / 向 Android 和 iOS 投递推送。它会收到设备推送令牌。多数通知为不含内容的唤醒；在 iOS 上，发给您本人的确认通知会携带文字，以便系统显示。</li>
          <li><strong>Apple Push Notification service:</strong> delivers notifications to iOS devices. / 向 iOS 设备投递通知。</li>
          <li><strong>Web push services of your browser:</strong> deliver web notifications; the payload is encrypted under the Web Push standard. / 浏览器的网页推送服务，用于投递网页通知；内容按 Web Push 标准加密。</li>
          <li><strong>Vercel and GitHub:</strong> host the web app and installer downloads. / 托管网页应用和安装包下载。</li>
        </ul>
        <p>
          Keep Contact 仅为运行上述功能而使用以上服务商。它们代表我们处理数据，受其自身隐私与安全承诺约束，并须对用户数据提供与本政策同等的保护。我们不会与广告商或数据经纪商共享数据。
        </p>
      </section>

      <section className="legal-section">
        <h2>6. Data Deletion & Account Erasure / 数据删除与账号注销权益</h2>
        <p>
          You may request deletion of your account and associated data at any time using the authenticated account deletion flow. The request is processed for the data associated with your authenticated account.
        </p>
        <p>
          您可以随时通过已验证身份的账号注销流程申请删除账号及关联数据。该申请会针对与您已验证账号关联的数据进行处理。
        </p>
        <div style={{ marginTop: '1rem' }}>
          <a href="/delete-account" className="legal-btn legal-btn--danger">
            Request Account & Data Deletion / 申请注销账号与删除数据
          </a>
        </div>
      </section>

      <section className="legal-section">
        <h2>7. Contact Us / 联系我们</h2>
        <p>
          For questions about this policy, contact <a href="mailto:support@keepcontact.app">support@keepcontact.app</a>. / 如对本隐私政策有任何疑问，请联系 <a href="mailto:support@keepcontact.app">support@keepcontact.app</a>。
        </p>
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
