---
type: project
status: active
project: Keep Contact
updated: 2026-08-21
---

# Keep Contact — 项目大脑

#project #kc #active

> **目的**：让用户在日常生活中，通过被动记录和主动关怀，互相确认彼此的安全与存在。
> **核心价值**：无需主动操作，只要"正常用手机"就够了。
> **目标形态**：长期、跨设备、隐私克制地理解每个用户与随身设备的 usual relationship，再判断当前沉默是否 unusually silent。

---

> ⚡ **AI 快速心智与不变量导航**：请优先阅读 [[Keep Contact Invariants & Map]]（~600 tokens），内含 5 层漏斗、不可违背的 5 条红线契约与精准模块下钻指针。避免盲目全量加载所有背景文档。

---

## 2026-08-21 当前生产与架构真相（v0.7.4）

[Antigravity · 2026-08-21 14:15 +06:00]

- **核心监测范式翻转（0.7.2+）**：彻底推翻旧网格（D×N）连续漏签模型，改为**「被动活动豁免每日签到（Daily Check-in with Activity Waiver）」**。每天在指定时间（`ask_at_local_minute`）询问一次，若回溯窗口（`waiver_lookback_minutes`）内有合格被动证据则自动豁免；即使采集器全挂，最坏情况也仅每天打扰一次（与传统签到基准相同），彻底消除打扰爆炸。
- **清醒滚动死线（0.7.4）**：截止时间基于清醒时间计算，睡眠窗不扣减清醒超时；窗口截止时间随窗口内最新活动证据动态后滚。
- **沉默原因精确分类（0.7.4）**：超时关闭时记录精确分类：`silent`（人无动静）、`device_unreachable`（设备断联）、`collection_restricted`（权限/采集受限），通知与健康系统按原因分流，绝不把技术 Outage 误报为人身危险。
- **精准敲门（0.7.4）**：仅在截止时间前 1 小时内向可能超时的对象发送敲门推送，不再全量唤醒；`my_daily_checkin` 统一返回服务端计算的 `next_deadline_at`。
- **版本与产物基线**：当前生产为 `v0.7.4`（HEAD `334c8e6` / `16647d8`），涵盖 Web/PWA、签名 Android APK/AAB、Tauri EXE/MSI（带 minisign 签名与 desktopOffer 防循环更新）、iOS TestFlight。
- **测试闸门**：Vitest 91 文件 / 518 测试全部 PASS，TypeScript 零错误。

## 2026-08-09 当前稳定化真相（历史记录）

[Codex · 2026-08-09 17:24 +06:00]

- **产品目标**：AAB、Tauri 与 iOS Native 是目标产品；APK 与 iOS PWA 只作过渡验证。功能完成的标准同时包含真实守护价值、平台限制下的诚实降级、商店审核可解释性与跨端一致性。
- **运行边界**：本轮只在隔离分支 `codex/kc-stabilization-s0` 做本地合并、测试与记录；未冻结或修改当前在线 App，未 push、部署、发布或改动远端 Supabase。
- **现状分层**：生产状态、仓库 `main`、本地稳定化分支、尚未交付的 Android/iOS/Tauri 客户端必须分别陈述，不得用“源码已有”冒充“用户已收到”。
- **守护契约**：健康且 coverage 可验证时尽量静默；设备、权限、后台能力或 App 已知失效时显示持续 `Limited`，不可用沉默让用户误以为守护正常；未知状态既不算安全，也不算危险。
- **告警契约**：被动活动只更新 activity/coverage，不解除告警；解除必须来自用户刻意动作、独立照顾者的外部确认，或 GM 的明确关闭。Concern 只能附着到现有告警，不能自行制造告警。
- **关系契约**：普通组员在名单中看状态；只有用户私下、默认关闭地勾选为 `Special Attention` 的成员才额外通知。Guardian/Ward 是最全面的持续守护关系，但不能冒充用户身份、生成用户本人活动、替用户授予设备权限或解锁设备。

当前缺口与测试红线见 [[Known Issues]]；本地证据见仓库 `docs/stabilization/s0-source-inventory.md` 与 `docs/stabilization/s0-db-test-baseline.md`。

### 渠道角色与实测现况（Chunwei 2026-08-10 口述 + 生产实测）

| 渠道 | 角色 | 现况 |
|---|---|---|
| **Android AAB** | **最终目标**，功能设计对象，含 Google 平台限制考量 | 未发布、未测试,仅作设计参照 |
| Android APK | AAB 的**临时实测替身**,能力必须按 AAB 对齐 | 在测;目前**唯一在产的覆盖凭据来源**(319 leases / 4 client / 3 用户) |
| **iOS Native** | **最终目标**，功能设计对象，含 Apple 平台限制考量 | 少量用户在测;**告活采集仍不确定、不稳定**,故尚未全面替换 PWA |
| iOS PWA | 早期测试渠道,告活全靠 Shortcut 设置 | iOS Native 能稳定实测后即放弃 |
| **Tauri（exe/msi，即「Windows Desktop app」）** | **最终目标**，功能设计对象，含 Microsoft/Linux 平台限制考量 | 已在实测(本机 0.5.25 自 2026-08-03 常驻至今);活动 ping 正常(1207 条/14 天),**覆盖凭据 0 条** —— 见 [[Known Issues]] |

**分层原则（Chunwei 定调，与 ADR-0040 D1 一致）**:告活信号的**采集与权限**因平台能力与限制不同而各自设计,但**核心理念必须一致**;后台的 **Routine 学习则统一且兼容**——它只消费归一化产出,不得引用任何平台词汇。

判断某个平台的实现是否合格,看它能否把自己的限制**如实翻译成归一化产出**(能力弱可以,谎报不行);判断学习层是否合格,看它能否在不知道平台存在的前提下正常工作。


---

## 系统如何运作（动任何功能前先读这一节）

KC 不是「一堆通知功能」，是**一条漏斗，每一层都在替下一层挡住不该到达的东西**。判断某个改动是好是坏，先问它落在哪一层、对下游是加压还是减压。

```
告活频率记录  →  判断线  →  ①本人自证  →  ②小群  →  ③社群
   (根基)      (触发条件)    (挡误报)     (人力)   (人力)
```

**根基 — 告活频率记录。** 设备持续收集「这个人还活着」的证据，后台学出他的真实节奏。**这是对账户的学习，不是对设备的学习**：同一账户在所有已登录设备上的记录合成一条流，设备只负责收集上报，统合与判断全在后台（[[Decisions]] ADR-0035）。这一层的质量决定下面的一切。

**触发条件 — 判断线。** 从上面的模型推出「多久没动静才反常到值得打扰人」。**它是统计判断，不是安全阈值。** 学得准，线就贴合这个人；学不准，只能退回通用模板，对谁都不合身。

**第①层 — 本人自证。** 线被触发时先只惊动用户自己：有声、醒目、要一个**刻意的动作**（手势解锁）。
- 这一层的作用是**消除误报**，不是安全。绝大多数触发只是这个人在忙、在开会、在睡觉；他解开了，事情就结束在这里，没有任何其他人被打扰。
- **手势是摩擦装置，不是身份凭据。** 因此明确排除生物识别——太快，抬手就过，对「病得很重却硬撑」的用户等于没有那道坎。不要用登录/凭据的思路去加固它。

**第②③层 — 人力。** 本人没回应，才把「确认这个人是否安全」一圈圈往外交：小群 → 社群。每一层扩大的都是**人的注意力投入**。到了群阶段之后应关闭 concern 选项，逼群成员直接联系本人（⚠ 该收紧尚未实现，见下）。

### 三条不可违反的规则

1. **有活动 ≠ 已回答。** 被动活动只更新在线状态，永不解除任何告警。告警只由本人手势解锁、认领者确认安全、或 GM 关闭。违反它，第①层就等于不存在——而且恰好在最该抓住的人身上失效（还在用手机、状态却很糟）。2026-08-02 之前这条一直是破的。
2. **越靠前的过滤失效，代价越由人承担。** 前面两层任一失效，压力全部落到人力层。
3. **误报的代价不是「吵」，是消耗群体的响应意愿。** 每一次「结果没事」的群通知，都在削弱下一次真事发生时大家起身的概率。第①层的价值不在少发几条通知，而在**保住社会资本，留给真正需要的那一次**。这也是「频率记录窗口尽量长」的理由：短窗口学到的是噪声，噪声推出来的线会持续误报，把信任烧光。

### 功能之间怎么配合

| 功能族 | 服务于哪一层 | 判断标准 |
|---|---|---|
| 推送通道、通知渠道重要性、锁屏亮屏、full-screen intent | 第①层的**送达** | 提醒能不能真的到人眼前 |
| 手势解锁、解锁界面即时顶出 | 第①层的**摩擦** | 是否需要一个刻意动作 |
| 频率学习、preset 群体模型、阈值收敛 | **根基与判断线** | 线是否贴合这个人 |
| 升级链、认领、守护者确认安全、紧急信息解锁 | 第②③层 | 人力投入是否用在刀刃上 |

**推送做得再好，也只是保证第①层的提醒送得到；它不会让判断线变准。反过来，判断线再准，提醒送不到也白搭。** 两者是同一层的支撑件与上游，不可互相替代。

### 各层现状（2026-08-02）

- **根基**：⚠ **一直没通电**。生产库有 66,047 条真实告活记录（10 用户 / 7 周），实际被采纳进阈值计算的样本只有 **2 条**；preset 群体模型产出 **0 行**。原因是学习路径读的是「影子评估体系」的产出，而那套为可重放审计而生、采纳条件极严。ADR-0035 已决定重构为账户级 + 群体锚定。
- **判断线**：⚠ 全体在跑通用模板。实测个人 p95 跨度 **29 分钟 ~ 1573 分钟（54 倍）**，而模板只有 135 / 180 两个值——**对一半人太松，对另一半太紧，同时错在两个方向**。
- **第①层摩擦**：✅ 2026-08-02 修复（活动不再解除告警）。
- **第①层送达**：✅ Android / iOS 均已打通（FCM 凭证、通知渠道、锁屏亮屏、点击直达解锁界面）。
- **第②③层**：✅ 升级链运作正常；⚠ 「群阶段后关闭 concern 选项」未实现，前端按钮只看是否告警中、不看阶段，服务器端 `send_concern` 同样无阶段限制。

### 给接手的 AI

改任何东西之前，先说清楚**它落在哪一层、对下游是加压还是减压**。历史上反复出现的错误是：抓住一个叶子节点修得很对，却没意识到它只是某层的支撑件，于是在错误的层上投入。另一类反复出现的缺陷形状是——**保护被写成对某个字段值的判断（如 `cause in (...)`），然后另一条分支绕开了它**；2026-08-02 一天之内咬了两次。

---

## 项目入口

%% WAYPOINT %%

### 🏗 架构（正确的样子）
- [[Product Requirement]] — living PRD: 产品问题、边界、验收标准
- [[System Design]] — living SDD: 模块边界、数据流、失败/回滚/观测
- [[System Overview]] — 技术栈、数据流、整体设计
- [[Database Schema]] — 所有表结构与字段含义
- [[Feature Modules]] — 前端各模块职责
- [[iOS Native TestFlight Pipeline]] — iOS 原生被动存活扩展 + GitHub Actions + TestFlight 自动化流水线 ⭐ (accepted, ADR-0033)

### 🎨 体验设计（动 UI 前必读）
- [[UX Framework]] — 目的×用户→设计原则 P1~P8、验证三层门、冲突裁决表 ⭐（accepted, ADR-0007）
- [[UX Audit 2026-07-06]] — 22 项时点发现(UXA-01~22,在沉淀区;带原则映射与批次)

### 📋 业务逻辑（核心规则）
- [[Alert System]] — 告警机制 ⭐ 最核心
- [[Usual Behavior Model]] — 长期 usual / unusual silence 判断的目标模型 ⭐ 最核心
- [[Behavior Pings]] — 活跃信号的唯一真相
- [[Sleep Window]] — 睡眠窗与时区处理
- [[Notification Flow]] — 通知分发链路
- [[Guardian Confirm]] — Guardian 确认安全流程
- [[Monitoring Direction]] — monitored / watching 双向开关

### 📝 历史与问题（在沉淀区）
- [[Dev Log]] — 改动意图记录
- [[Known Issues]] — 问题追踪
- [[KC Project Completeness Review 2026-07-06]] — 当前项目完整性 review
- [[KC Improvement Plan 2026-07-06]] — 商业级基线补强计划

### 🧭 决策与协作
- [[Decisions]] — 本项目 ADR 决策日志（`accepted` 的约束所有 IDE）
- [[Coordination]] — 多 IDE 协作协议
- [[SDLC Unified Workflow]] — 统一工程流水线（active v2.7，所有 IDE 必读；M4 三强仅顶层策划，M0–M3 cheapest-fit 单 owner 默认；ADR-0012 execution collaboration 为 Brain-global，不是 KC 专用）

---

## ⚡ 给 IDE/AI 的核心原则

> 在处理任何 KC 代码前，必须遵守：

1. **`behavior_pings` 是活跃证据事实表；canonical v2 才是 live safety 真相** — 不要用 `device_state.last_heartbeat_at` 或裸 `max(at)` 做业务判断。只用共享服务端 validator 写入、`ingest_version=2` 且通过 `received_at`/drift/causality gate 的证据；历史 v1/离线 replay 只供审计与分析。见 [[Behavior Pings]]

2. **KC 的核心不是固定 timeout，而是 usual behavior model** — `silence_threshold` / `hourly_thresholds` 只是当前过渡输出；最终目标是长期、跨设备、带 confidence 的 unusualness 判断。见 [[Usual Behavior Model]]

3. **睡眠窗用本地时钟数字** — `sleep_start_utc`/`sleep_end_utc` 存的是用户本地时间数字，服务端判断时须先将 `now()` 转为用户时区（`user_settings.timezone`）

4. **Guardian 确认 ≠ 用户自身确认** — Guardian 确认安全后，保留/重发用户自身的 nudge 通知，不能替代用户本人产生真实 ping

5. **monitored 和 watching 是独立开关** — 两者不互相绑定，用户可以单独开启其中任一

6. **Migration 只新增，不修改旧文件** — 任何数据库改动都创建新 migration 文件

7. **零新增费用是默认硬约束** — 优先免费、开源、本地可复核方案；任何付费、按量、需绑卡、专有-only 或费用不明选项必须先取得人类明确同意，不能以“验证方便”为由先启用

---

## Encoding guardrail

- When editing `src/lib/i18n.tsx`, Obsidian Markdown, or any file with Chinese / emoji / typographic punctuation, do **not** route file contents through PowerShell text pipelines, `cmd /c >`, or tools that may change encoding. Use a UTF-8-safe editor/API: `apply_patch` when available, or Node/Python read/write with explicit UTF-8 and then inspect `git diff` for text diff. If Git shows the file as binary or the diff is mojibake, stop and restore before continuing.

## 技术栈速查

| 项目 | 技术 |
|---|---|
| 前端 | React + Vite + TypeScript（PWA / Capacitor）|
| 样式 | Vanilla CSS（CSS Variables）|
| 后端 | Supabase（PostgreSQL 17）|
| 定时任务 | pg_cron（每分钟 `process_escalations`）|
| 推送 | Web Push（VAPID）/ APNs 静默推送 |
| 本地存储 | IndexedDB（35 天信号历史）|

---

## 参考
- [[Supabase Patterns]] — 通用 Supabase 规范（在 References）
- [[Alert Architecture]] — 通用沉默告警设计（在 References）
- [[Dev Workflow]] — 轻量开发伴随清单（正本见 [[SDLC Unified Workflow]]）

### 🧪 QA 与平台矩阵
- [[Scenario Matrix]]
- [[Platform Device Matrix]]

### 🛡 运营与安全
- [[Release Runbook]]
- [[Security Privacy Baseline]]
- [[Security Privacy Review 2026-07-06]]
- [[Google Play Store Compliance]]
- [[Accounts]] — 服务账号映射（IDE 操作前必读）

[Codex · 2026-07-29 09:21 +06:00] Current production release: `v0.5.21` at `main@51212f0`, including Web/PWA, Android APK, Tauri installers, and the default-off ADR-0028 adaptive-shadow foundation. See [[Adaptive Shadow Release Readiness 2026-07-29]].

[Codex · 2026-07-29 23:04 +06:00] Current production release: `v0.5.22` at `main@2ccec6c`, shipped across iOS/Web PWA, signed Android APK, and Tauri NSIS/MSI after canary and independent audit. GM mute is the accepted narrow exception for suppressing only new incorrect silence/dark-device alerts; existing alerts continue. Adaptive Cron remains zero and ADR-0022 remains the normal live authority. See [[KC v0.5.22 Release Readiness 2026-07-29]].

[Antigravity · 2026-08-21 14:20 +06:00] Current production release: `v0.7.4` at `main@334c8e6` / `16647d8`, incorporating rolling awake deadlines, named silence cause, targeted knock, Routine & Me UI redesign, and Tauri minisign release bundles across PWA, Android APK/AAB, Tauri EXE/MSI, and iOS TestFlight.

[Codex · 2026-08-30 20:58 +06:00] Collection-permission repair landed in the working tree: canonical capability registry/resolver now distinguishes Android APK/AAB, iOS TestFlight/App Store, Tauri, and PWA; Me > Collection permissions exposes live permission states and sensor toggles without duplicate Android controls; native bridges expose general app-settings deep links. Typecheck and targeted passive tests pass. Device/TestFlight/AAB runtime verification remains open.

