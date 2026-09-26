# KC 原生机制修复记录

[Codex · 2026-09-27 01:17 +06:00]

分支：`codex/kc-native-mechanism-repair`。本地实现与回归已完成，尚未发布。
基线 `6ef806e` 已包含 TestFlight 0.7.8 (44) 的 HealthKit 历史查询修复。

| 审查项 | 修复结果 |
| --- | --- |
| M01 iOS 后台唤醒冒充本人活动 | 移除 wake-sample 活动来源并过滤旧队列；实际交互、解锁和有证据的历史采集各自保留。 |
| M02 历史步数被标成当前活动 | 有界查询定位最近的正证据区间，以保守区间起点上报；成功读取或持久化后才提交游标。 |
| M03 Tauri 旧输入重复记成新活动 | 保留真实输入时间；Windows 输入 tick、macOS 开机会话及单调时钟标识用于跨采样去重。 |
| M04 旧通知确认新告警 | 动作绑定通知、原告警、收件账号和推送绑定；服务端拒绝空告警 ID；旧无范围动作仅导航。 |
| M05 热启动通知动作漏处理 | 原生持久队列、冷/热启动捕获、完成回执与逐条重试；一条失败不阻塞其余动作。 |
| M06 Android 静止时离线队列不重试 | 独立 WorkManager 网络约束任务，区分暂时/终止错误；原事件身份和时间保留。 |
| M07 Tauri 初始化失败永久停采 | 启动即安装恢复机制、退避重试、15 秒上传超时；撤销绑定保持 Limited，用户明确重开后重新登记。 |
| M08 Tauri 重启丢离线队列 | 同账号恢复同一绑定，旋转内存凭据、保留事件与序号；不同账号保持隔离。 |
| 退出后旧账号推送 | 原生停止接收并清理通知；持久化仅可撤销的任务，重新联网时无需用户会话即可解绑。兼容旧 FCM token 的精确删除已获用户明确授权。 |
| Tauri 托盘签到 | 使用正式 Tauri 事件 API，卸载清理监听并验证账号归属。未增加桌面系统通知。 |

复核另外修复：退出后的旧采集配置回调、账号切换期间延迟上传、过期会话及在途刷新阻塞退出、通知队列首项失败、APNs kind 与 feed 版本不一致。旧 token 仅用于删除未迁移的精确匹配旧记录；已绑定的新记录不会被旧任务删除。

## 验证

- `npm test -- --reporter=dot`：112 文件、677 测试通过，包括真实认证 SDK、通知队列、Tauri 恢复和 PGlite SQL 边界回归。
- `npm run typecheck`、`npm run build`：通过；构建仍有已有的大 chunk 和混合静态/动态导入提示。
- `android/gradlew.bat :app:testDebugUnitTest --offline`：Java 编译及 14 项 JVM 测试通过。
- `src-tauri/cargo test --offline`：Windows 原生编译及 8 项 Rust 测试通过。
- 独立客户端与服务端复审：所列问题修正后，限定复审没有剩余 P1/P2。

以上不替代真机端到端验证。

## 尚待验证与发布门槛

1. 当前主机没有 Xcode/Swift 或 macOS SDK，不能在这里确认 iOS 编译和 macOS 原生链接。Foundation 测试入口：

   ```sh
   swiftc ios-passive-ping/ios/Sources/KcPassivePingPlugin/MotionEvidenceWindow.swift ios-passive-ping/ios/Sources/KcPassivePingPlugin/NotificationActionQueue.swift scripts/test-ios-native-mechanisms.swift -o /tmp/kc-ios-mechanisms
   /tmp/kc-ios-mechanisms
   ```

   随后需 Xcode 完整 app 编译、macOS Tauri 编译。
2. 设备验证：无密码 iPhone 静默唤醒不得产生本人活动；历史运动不得冒充新活动；通知冷/热启动、旧告警与新 SOS 隔离；离线退出/重启/重新登录与旧 token 解绑；Android 无新活动时恢复上传；桌面休眠/调时/重启及托盘签到。
3. 本次只新增本地 SQL，未修改生产：`20260925021935_native_mechanism_integrity.sql`、`20260926184133_resume_passive_collector.sql`、`20260926184136_push_binding_revocation.sql`。发布需先验收迁移与 `notify-feed` / `push-dispatch` 配套，再分发新客户端。旧客户端无范围确认会被拒绝，需升级。
4. 没有更改公开版本号、签名或上传 TestFlight/APK/AAB/Tauri 安装包；主工作区原有改动保留。
