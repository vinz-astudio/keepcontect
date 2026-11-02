# iOS 告活:删除显著位置唤醒 + 让每日询问在 iPhone 上答得到 — 实现方案

- **日期**:2026-11-02
- **作者**:Claude Code
- **人类决定(2026-11-02)**:删除显著位置变化唤醒;做"时效性询问 + 补交证据"(推荐方案第 2 条)。
  不做:iOS 证据到达宽限时间调整(第 4 条)、后台刷新任务、锁屏免解锁确认。
- **状态**:D1、D2 按推荐确认(人类 2026-11-02);已实施,见第 8 节。

## 1. 为什么这样做(一句话版)

iPhone 拔电时,苹果不保证任何后台唤醒(24 小时实验:拔电响应 0)。所以 iPhone 的告活靠**一次能答到的询问**兜底,
后台证据只用来减少询问。显著位置唤醒收益低(拔电时每周 0–3 次),而且"始终允许定位 + 从不读取位置"
的组合在 App Review 5.1.5 / 2.5.4 下有拒审风险,也违背"不靠定位"的产品承诺。

## 2. A 部分:删除显著位置变化唤醒

### 现状(代码事实)
- `ios-passive-ping/ios/Sources/KcPassivePingPlugin/PassiveGuard.swift`:类实现 `CLLocationManagerDelegate`,
  `arm()` 调 `armRecoveryWake()` → `requestAlwaysAuthorization()` + `startMonitoringSignificantLocationChanges()`;
  `locationManagerDidChangeAuthorization` 在授权后再次布设;`didUpdateLocations` 只做 `captureSample("location-relaunch")`。
- `ios/App/App/Info.plist`:有 `NSLocationAlwaysAndWhenInUseUsageDescription`(2026-08-14 加回)。
- `scripts/s1-platform-contract.test.mjs` 的 `ADR0039-IOS-01` 断言这段说明**必须存在**。
- 数据库 `device_activity_samples_trigger_check` 允许 `'location-relaunch'`。
- SOS 定位走 WebView 的 `navigator.geolocation`(`src/lib/geo.ts`、`HomeScreen.tsx`),只需"使用期间"权限,与本次无关。

### 改动
1. **PassiveGuard.swift**
   - 删除 `CLLocationManagerDelegate` 实现、`locationManager` 属性、`armRecoveryWake()`、三个定位回调、
     `arm()` 里的调用、`disarm()` 里的停止,以及类头和方法上关于显著位置唤醒的注释。
   - **新增一次性清理**:每次进程启动(`resumeIfConfigured()` 及插件 `load()`)执行
     `CLLocationManager().stopMonitoringSignificantLocationChanges()`。
     原因:显著位置监听的注册**跨 App 更新保留**,不主动停止,系统会继续用定位事件把新版 App 拉起来。
     停止调用不需要任何权限、不弹窗。保留至少两个版本,之后再删。
2. **Info.plist**:删除 `NSLocationAlwaysAndWhenInUseUsageDescription`;保留 `NSLocationWhenInUseUsageDescription`(SOS)。
3. **契约测试** `ADR0039-IOS-01` 改写为:
   - Info.plist 不含 `NSLocationAlwaysAndWhenInUseUsageDescription`、不含 `UIBackgroundModes: location`;
   - iOS 源码不含 `requestAlwaysAuthorization`、`startMonitoringSignificantLocationChanges`、`startUpdatingLocation`;
   - 允许且仅允许 `stopMonitoringSignificantLocationChanges` 出现(清理用)。
   先改测试使其失败,再改代码。
4. **服务端不改**:`'location-relaunch'` 继续留在允许值里,旧版客户端在升级前还会发。不需要迁移。
5. **已授权"始终"的用户**:系统权限无法由 App 收回,但 App 不再使用定位,也不会再弹窗。发版说明写一句
   "可在 设置 › Keep Contact › 位置 改为'使用 App 期间'"。
6. **Brain 记录**:L3 教训和 iOS 整理(12 号文件)要更正,写明 2026-08-14 曾恢复显著位置唤醒、
   2026-11-02 人类决定删除。见第 7 节回写清单。

## 3. B 部分:安全询问使用"时效性通知"

### 作用
时效性通知(iOS 15+)会穿透专注模式和通知摘要,点亮屏幕;用户可在系统设置里对 KC 关闭。
这是苹果为"需要立即处理"的通知提供的正规级别,不需要审批(区别于需特批的 Critical Alerts)。

### 范围(待确认,见第 5 节 D1)
推荐只给这四类:
| kind | 收件人 | 理由 |
|---|---|---|
| `self` | 本人 | 每日询问 / 本人确认,答不到就会升级 |
| `concern` | 本人 | 有人在关心,需要本人回应 |
| `sos` | 守护圈 | 本人主动求救 |
| `terminal` | 守护圈 | 真实沉默的最后一级 |

`group` / `community` 保持普通级别:方案 A 之后它们多是"KC 失去联系",不应打断别人的专注模式,保护社会资本。

### 改动
1. **Entitlement**:`ios/App/App/App.entitlements` 增加 `com.apple.developer.usernotifications.time-sensitive = true`。
2. **App ID 能力**:`ios/App/fastlane/Fastfile` 仿照现有 HealthKit 的做法,在 App ID 上开启 Time Sensitive Notifications
   能力(能力的确切名称以 Apple Developer 后台为准;也可以先在后台手动开一次)。缺了它签名会失败,不会静默出错。
3. **服务端推送** `supabase/functions/push-dispatch/index.ts`:可见推送的 `apns.payload.aps` 增加
   `'interruption-level': 'time-sensitive'`(仅上表四类),其余显式 `'active'`。
   兼容性:App 没有该 entitlement 或系统低于 iOS 15 时,系统按普通通知处理,不会出错,所以服务端可以先于 App 上线。
4. **iOS 本地通知** `NotifyFeed.swift` 的 `post()`:同四类设置
   `if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }`(最低支持 iOS 14,必须按版本判断)。
   `post()` 现在只收 `body/id/metadata`,需要把 `kind` 传进来。
5. **诚实显示**(见 D2):权限中心读取 `UNNotificationSettings.timeSensitiveSetting`,
   用户关闭时显示"受限:专注模式下可能收不到 KC 的安全询问",不画假绿灯。
6. **"一切安好"按钮保持 `.foreground`**:确认由网页层用登录会话完成(M04/M05 修复后的设计),
   改成锁屏免解锁会让原生凭据获得"确认告警"的权限,扩大攻击面。本次不改。

### 测试
- 契约测试:entitlement 存在;`push-dispatch` 对四类输出 `time-sensitive`、其余 `active`;
  `NotifyFeed.swift` 含 iOS 15 判断与同一四类映射;Android/Web 不受影响。
- 若 `push-dispatch` 的消息构造函数可导出,补单元测试;否则用静态契约测试(仓库已有先例)。

## 4. C 部分:补交证据 — 核对结论与真实上限

### 现有运行入口都已补交
| 入口 | 已调用 |
|---|---|
| 回到前台 / 解锁 | `HealthWake.retryHistory()` + `captureSample("foreground"/"unlock")` |
| 静默推送 | `handleWake` → `retryHistory` + `captureSample("push-wake")` |
| HealthKit 唤醒 | `captureSample("health-wake")` |
| 点通知的"一切安好"(会打开 App) | 走"回到前台"路径 |
| 显著位置唤醒 | 本次删除 |

结论:**不需要新代码**,只需在真机上验证"从锁屏点按钮冷启动"时,前台补交确实在 `arm()` 之后触发。
验证发现缺口再补。

### 上限(写清楚,不夸大)
- 历史补传的证据**不能解除告警**(ADR-0045:历史补传不得冒充本人新活动)。
- 只有在签到窗口的到达宽限时间之内送达,才能免掉当期询问;超时送达的证据只进入记录和学习。
  放宽 iOS 宽限时间就是未选的第 4 条,需另走 ADR。
- 所以 B 部分(询问答得到)才是本次的主要收益,补交只是锦上添花。

## 5. 待人类确认

- **D1**:时效性通知范围是否按第 3 节的四类(`self`、`concern`、`sos`、`terminal`)?推荐:是。
- **D2**:权限中心是否显示"时效性通知已关闭"的受限状态?推荐:是,改动很小。

## 6. 实施顺序与发布

1. 分支上先写失败的契约测试,再改 iOS 代码、Info.plist、entitlement、Fastfile、push-dispatch。
2. 全量 vitest + typecheck + iOS CI 自带的 Swift 检查。
3. 触发 iOS TestFlight 构建(这一步我可以做)。
4. `push-dispatch` Edge Function 部署:**生产操作,需人类批准**。兼容旧 App,可在 TestFlight 前后任意时间部署。
5. 无数据库迁移;Android、网页不受影响。

### 真机验收(需人类在 iPhone 上做)
1. 打开专注模式 → 本人询问照样弹出并点亮屏幕。
2. 设置里关闭 KC 的时效性通知 → 询问变普通通知;权限中心显示受限(若做 D2)。
3. 全新安装 → 全程**不出现**定位"始终允许"弹窗;SOS 时仍会请求"使用期间"定位。
4. 从旧版升级 → 新版本不再产生 `location-relaunch` 采样(生产按 `app_version` 统计可核对)。
5. 锁屏点"一切安好" → 解锁后确认成功,告警解除。
6. 拔电走路一段时间后打开 App → 健康/运动证据以原始时间补交成功。

## 7. Brain 回写清单(给有 Brain 权限的 agent)

- Decisions 快记:2026-11-02 · 决定 · 删除 iOS 显著位置变化唤醒与"始终"定位说明 · 理由:拔电时收益每周 0–3 次;
  App Review 5.1.5/2.5.4 拒审风险;与"不靠定位"冲突 · 来源:人类。
- Decisions 快记:2026-11-02 · 决定 · iPhone 告活以"答得到的询问"兜底,后台证据只减少询问;
  安全询问用时效性通知 · 来源:人类。
- 更正 L3 与 12 号 iOS 整理:补记 2026-08-14 曾恢复显著位置唤醒(代码注释称人类决定),2026-11-02 删除。
- Known Issues:iOS 拔电 HealthKit 唤醒自 0.7.8/0.7.9 发布那周起从每周 20–58 次降到 0–1 次(插电正常),
  原因未查明,需真机日志;唯一测试机疑似无锁屏密码(采样中受保护数据始终可用),数据不具代表性。

## 8. 实施记录(2026-11-02)

- A 部分:已删除定位唤醒、"始终"定位说明;启动和停用时调用 `clearLegacyLocationWake()`。
- B 部分:entitlement、Fastfile 能力、`NotificationUrgency.swift`(iOS)与 `push-dispatch/interruption.ts`(服务端)同一份四类名单;
  `NotifyFeed` 按 iOS 15 判断设置级别;iOS CI 编译并执行该规则。
- D2:原生层 `getNotificationPermissionStatus()` 新增 `timeSensitive` 字段;判断逻辑在 `src/features/passive/timeSensitiveNotice.ts`(含测试)。
  **接入权限中心界面暂缓**:读取通知权限的 `native.ts` 和权限中心的 `guardianPermissions.ts`、`GuardianPermissionsCard.tsx`
  都在人类本机未提交的 7 个文件里,现在改会冲突。等那批改动推上来后,只需几行把 `timeSensitiveLimitation()` 接进通知那一行。
- C 部分:核对完毕,无代码改动。
- 测试:全量 vitest 115 文件 / 736 用例通过,typecheck 通过。本机无 Swift 编译器,Swift 由 iOS 流水线编译执行。
- 未做:`push-dispatch` 生产部署(待人类批准)、真机验收(第 6 节)。
