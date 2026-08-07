# Android 设计约束 — 以 Google Play 能过审为前提

**读这一页再动 Android 的通知、后台或权限。**

APK 和 AAB 是同一份代码。KC 迟早要上 Play Store,所以**"APK 上测着好用"不是验收标准,"AAB 能过审且行为一致"才是**。
先做完再检查合规,等于把已经测好的功能推倒重来 —— 这已经发生过一次(见下方 full-screen intent)。

## 判断顺序

动任何 Android 后台/通知能力之前,按这个顺序自问:

1. **这个能力需要 Google 逐案批准吗?** 需要 → 默认当作**拿不到**,先把没有它也能成立的方案设计出来。
2. **拿不到时系统是报错还是静默降级?** 静默降级最危险 —— 代码看着对、评审看着对,测试机上行为不同,而且没人知道走了哪条路。**必须显式检测,不能假设。**
3. **不批准会死掉哪个用户价值?** 如果答案是"核心价值",那这个设计本身就不该依赖它。

## 当前状态

### 前台服务 `specialUse` — 承重,已按要求声明

`KcForegroundService` 是 Android 侧告活的承重结构:`ACTION_USER_PRESENT`(解锁)**不在 Android 8+ 的隐式广播豁免名单里**,manifest 注册收不到,只有前台服务里运行时注册的接收器才拿得到。砍掉服务 = 解锁告活直接消失。

- `android:foregroundServiceType="specialUse"` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`
  = `"Emergency and personal safety monitoring for lone dwellers"` —— Play 要求的声明已就位
- **不能改用 `dataSync`**:Android 15 起它有每天 6 小时运行上限,会掐死守护
- `health` 面向健康/健身,与人身安全监护不同类

提交时 Play Console 会人工审这段用途说明,重点回答两件事:**为什么必须常驻**、**为什么其他类型都不适用**。

### 全屏意图 — 已降级为可选,不得再依赖

Android 14 起 `USE_FULL_SCREEN_INTENT` 只自动授予核心功能是**来电或闹钟**的应用,其余需向 Play 单独申请,人身安全类**大概率拿不到**。

拿不到时系统**静默降级**成普通 heads-up 通知 —— 所以 2026-08-01 那次"让 concern 点亮屏幕"的改动,**在 Android 14+ 上可能一直没有生效,而没有任何人察觉**。

现在 `NotifyWorker.canUseFullScreenIntent()` 会在使用前实际检测(API 34+ 查 `NotificationManager.canUseFullScreenIntent()`),拿不到就不调用。

**唤醒能力由通知渠道承担,不由这个权限承担**:`IMPORTANCE_HIGH` + 显式声音 + 震动 + 呼吸灯 + `VISIBILITY_PUBLIC`。这些在所有设备上都能把手机叫醒,且不需要 Google 批准任何东西。

> 往后若有人想再让 concern"更强硬地"抢占屏幕:那条路是关的。要提高触达,改渠道、改文案、改升级时序,不要再往这个权限上压需求。

### 常驻通知 — 只能压到最低,不能隐藏

API 26+ 前台服务**必须**有通知,应用无权隐藏。能做的已经做满:

| 措施 | 效果 |
|---|---|
| `IMPORTANCE_MIN` | 状态栏无图标,折叠在通知栏底部静默区 |
| `setShowBadge(false)` | 桌面图标无红点 |
| `setOnlyAlertOnce(true)` | 重复 post 不当新消息 |
| `FOREGROUND_SERVICE_DEFERRED` | Android 12+ 延后约 10 秒显示 |
| 复用同一个 `Notification` 实例 | 服务被反复启动时不重新宣告 |

**用户划掉它之后要能保持划掉。** Android 13+ 允许滑掉前台服务通知,但之前每次解锁都会重新 post,使划除失效 —— 那是 bug,已修。**不要再引入任何"定期重新 post 常驻通知"的逻辑。**

### `PACKAGE_USAGE_STATS`

受保护权限,由用户在系统设置里授予。Play 要求核心功能确有必要并做**显著披露**(prominent disclosure)。
`native.ts` 里已有中英双语披露弹窗,改动这块时必须保留。

## 提交 AAB 前的检查清单

- [ ] Play Console 填写 `specialUse` 用途说明(为什么必须常驻 / 为什么其他类型不适用)
- [ ] 数据安全表单覆盖:运动与健身、健康(iOS 侧)、位置(仅 SOS 且需用户同意)、通知
- [ ] `USE_FULL_SCREEN_INTENT`:要么申请,要么确认不申请也不影响核心流程(当前设计是后者)
- [ ] `PACKAGE_USAGE_STATS` 显著披露截图
- [ ] 真机验证 Android 14+ 上 concern 告警**没有** full-screen intent 时是否仍能叫醒用户
