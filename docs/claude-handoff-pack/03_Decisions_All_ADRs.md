---
type: decisions
project: Keep Contact
---

# Keep Contact — 决策日志 (ADR)

#kc #decisions

> 项目级架构 / 业务**决策**记录。`accepted` 的对所有 IDE 有约束力。
> 新决策追加在**底部**、编号递增，不改旧条目（只改状态：`proposed` → `accepted` / `superseded`）。
> 流程见 [[Coordination]]。格式：编号 · 日期 · 状态 · 决策 · 理由 · 影响。

---

## ADR-0001 · 2026-06-13 · accepted
**决策**：`behavior_pings` 为活跃状态的唯一真相；`device_state` 仅作缓存（由 ping trigger 用 `greatest()` 维护）。业务判断查 `max(behavior_pings.at)`，不直接信 `device_state.last_heartbeat_at`。
**理由**：多设备 / 历史同步下，心跳缓存可能被旧数据覆盖或滞后；以行为记录为真相最稳。
**影响**：`process_escalations`、`get_group_activity`、GM 状态等；落实见 `20260613045845_behavior_pings.sql`、`20260624200000_gm_status_use_behavior_pings.sql`。
**追溯**：本条为接入协作协议时，把既有核心原则补登为 ADR（见 [[Keep Contact]] 核心原则 #1）。

---

## ADR-0002 · 2026-06-27 · accepted
**决策**：开始实现 Personal Usual Behavior Model v1。模型目标是用长期、跨设备、隐私克制的 behavior metadata 学习每个用户的 usual relationship，并把 silence 判断从固定 timeout 逐步迁移为 “baseline threshold + confidence + explanation + sensitivity tool”。`sensitivity` 是用户快速调节工具：`high/sensitive` 尽量贴近模型算出的 threshold（允许约 30 分钟 buffer），`balanced` 和 `low/relaxed` 只在模型输出上延长触发时间，不能反过来污染模型 baseline。
**理由**：KC 的安全价值来自理解“这个人在这个时段/设备组合下通常会不会沉默这么久”，不是给所有人套固定小时数。用户需要一个简单的 sensitivity 控件来快速调节误报/漏报倾向，但模型本身必须保持中立和可解释。
**影响**：允许新增 additive migration / profile metadata / pure model helper / Edge Function prompt-output 扩展；v1 不删除旧 `hourly_thresholds` 兼容路径，不立即做 1 年 raw retention 或完全替换 `process_escalations`。后续 raw retention policy、长期聚合表、runtime unusualness score 全面替换仍需单独设计和验证。
**追溯**：人类在 2026-06-27 明确指出 sensitivity 应属于 tools，并要求开始开发 behavior model；见 [[Usual Behavior Model]]。

---


## ADR-0003 · 2026-07-06 · accepted
**决策**：Keep Contact 以及本 Brain 关联的项目工作统一采用 [[SDLC Unified Workflow]] active v2.1 作为默认工程协作协议；旧 [[ADR-0003 Unified Eng Pipeline]] draft 与 [[SDLC v2 Unified Workflow]] proposal 均作为历史溯源保留，不再作为执行正本。
**理由**：原 SDLC v2 已解决多 IDE 撞车、scope/non-scope、证据回报、交叉审计等核心协作问题，但缺少工业级流程常见的风险分级、安全/隐私/供应链、发布回滚、运营监控、traceability、Definition of Done。v2.1 将这些补成轻量 gate，保持 Brain 协议可执行而不过度官僚。
**影响**：所有 IDE 动手前必须读取 [[SDLC Unified Workflow]]，先分类 Tiny / Standard / Product-UX / High-risk / Release / Emergency，再按对应 gates 执行、验证、审计和回写。重大/不可逆/高风险仍必须先有人类 accepted ADR。
**追溯**：人类在 2026-07-06 要求 Codex review SDLC v2 后直接整理为新流程并让 Obsidian 链接的 IDE 统一遵循。

---

## ADR-0005 · 2026-07-06 · accepted
**决策**：将 [[SDLC Unified Workflow]] 升级为 active v2.2，本机执行层正式生效：`Templates/Engineering/` 模板、`Coordination/Commands/` 命令卡、`Coordination/tools/sdlc-check.mjs` 体检脚本、Active Work TTL/stale 规则、全局 IDE bridge 读取新协议。
**理由**：v2.1 已有成熟流程骨架，但仍偏文档协议。v2.2 把个人电脑能做的执行保障落地，让多 IDE 不靠记忆和自由发挥，而是通过同一套模板、命令卡和本地检查进入 SDLC。
**影响**：任何 IDE 生成 PRD/SDD/Spec/Task/Audit/Release/Incident 产物时，应优先使用对应模板和命令卡；改协议/adapter/template 后必须运行本地体检脚本并回报结果。
**追溯**：人类在 2026-07-06 要求继续完善，尤其把个人电脑即可做到的事项尽量设置到最好。

---

## ADR-0006 · 2026-07-06 · accepted
**决策**：[[SDLC Unified Workflow]] 升级为 active v2.3，并将 [[Industrial Obsidian IDE Framework]] 作为工业级轻量开发框架基线。该框架已达到可辅助 development 初学者进行严肃项目开发的成熟度；后续不再预先堆流程，除非真实项目 retro 证明有重复失败。
**理由**：当前框架已经覆盖单一协议、风险分级、ADR、人机职责、模板、命令卡、本地检查、Brain 分区、低 token 交接和回写闭环。继续抽象流程的边际收益低，下一阶段成熟度应来自 KC 等 Projects 的实战反馈。
**影响**：后续工作优先应用框架到项目，不继续为框架本身追加规则。流程改动必须来自实际项目中的重复问题、验证失败、release/security incident、token 浪费或 Brain truth 失配。
**追溯**：人类在 2026-07-06 明确目标：用 Obsidian+IDEs Framework 辅助 development 初学者避开工业环境已知坑，低 token 少走弯路，并询问是否已经达到可暂告一段落的水平。

---

## ADR-0004 · 2026-07-05 · accepted
**决策**：KC 的通知送达按平台分治。Web/PWA 继续使用 Web Push；Android 原生 APK 使用 WorkManager 轮询 `notify-feed` + 本地通知作为可靠兜底，并使用 FCM data-only tickle 作为 GMS 设备快路径；Tauri/WebView2 桌面通知作为明确 backlog，后续走 Tauri notification/tray API 或轮询方案。
**理由**：Capacitor WebView 不支持 Web Push / Notification API，Android APK 不能依赖浏览器 PushManager。FCM 只作为空唤醒信号，不承载通知内容，避免把敏感通知正文交给 Google；无 GMS/OEM 限制时仍有 WorkManager 轮询兜底。
**影响**：Android APK 通知不再被视为 Web Push 能力；`notify-feed`、`NotifyWorker`、`push_tokens`、FCM service-account secret、`push-dispatch` FCM tickle 共同构成 Android 平台通道。Tauri 通知仍需单独任务，不得误认为已完成。
**追溯**：2026-07-05 已按人类批准实现 Phase 1/2 并发布 0.5.13/0.5.14；2026-07-06 由 Codex 根据“处理 Batch A/B”指令补登 accepted ADR。源文件见 [[ADR-0004 Platform Notification Delivery]]。

---

## ADR-0007 · 2026-07-06 · accepted
**决策**：接受 [[UX Framework]] 作为 Keep Contact 的正式 UX/UI 约束。所有 IDE 修改 UI/UX、通知文案、危机路径、onboarding、Pattern/SOS/alert flow 时，必须引用相关 P 编号/UXA 编号，并按框架要求做 L1/L2/L3 验证。
**理由**：KC 是安全感产品，不是普通管理后台。其 UI 成功态是“平静且可信”；P1-P8 把平静技术、单一真相、危机零学习、第二人称文案、隐私尊严、角色自适应、触碰反馈、平台如实这些原则固定下来，能防止多 IDE 在 UI 上自由发挥。
**影响**：[[UX Audit 2026-07-06]] 的 UXA-01/02/03 成为下一批 P0 UX 修复候选；与 UX Framework 冲突的 UI 改动必须先走 Active Work / ADR。
**追溯**：人类在 2026-07-06 指示“处理”下一步 Batch A/B，视为接受 UX Framework 和平台通知架构补登。

---

## ADR-0008 · 2026-07-06 · accepted
**决策**：迁移 Android 平台后台被动活跃监测架构。逐步淘汰基于无障碍服务（`AccessibilityService` / `AppActivityService`）的主流依赖，改用“`UsageStats` (应用使用情况统计) + `Activity Recognition` (活动识别) + 系统广播 + 前台服务（带引导白名单设置）”的复合被动信号架构。
**理由**：Google Play 严禁非残障辅助类应用使用无障碍 API，面临极高下架风险。虽然无障碍服务在划掉后台后免自启动拉活，但 `UsageStats` 结合以下技术补偿可实现同等高保活监测：
1. **使用情况回溯**：`UsageStats` 允许在进程被强杀后复活时，通过查询系统日志回溯被杀期间的真实活跃时间戳，消除了单次查杀造成的误报。
2. **白名单引导补偿**：通过前端强引导用户为 App 开启“自启动”和“忽略电池优化”（电池无限制），防止划掉后台时被系统置于 Force Stop 状态。
3. **前台服务守护**：运行一个极轻量的紧急安全监护前台服务（`FOREGROUND_SERVICE_SPECIAL_USE`），保证系统高优先级。
**影响**：
1. **Manifest 与权限**：新增 `PACKAGE_USAGE_STATS`（特殊使用权限，需跳转系统设置）及 `ACTIVITY_RECOGNITION`（运行时权限）。
2. **原生插件扩展**：增加检测/引导开启使用情况访问和自启动设置的原生 Capacitor 接口；实现 `UsageStatsScanner` 和 `ActivityTransitionReceiver` 并发送 ping 信号。
3. **前端引导 UI**：在 Onboarding/Me 页面新增直观的“保活白名单设置向导”，针对 HyperOS、ColorOS、HarmonyOS 提供特定的锁定后台/自启动设置图文指引。
4. **Play 商店合规**：不再向普通用户索取极敏感的 Accessibility 权限，扫清上架的核心障碍。
5. **低能耗设计硬性要求 (Critical Battery Optimization)**：
   - **禁止高频轮询**：`UsageStats` 查询必须是事件触发或超低频定时（例如 15-30 分钟一次），或仅在被服务器静默 FCM 唤醒时执行。
   - **硬件级传感器整合**：`Activity Recognition` 必须使用 Google Play 服务的硬件级传感器融合（Transition API），禁止直接调用高功耗的原生加速度传感器监听器（`SensorEventListener`）以防止 CPU 无法进入深睡（Deep Sleep）。
  - **零计算前台服务**：前台服务只作为系统绑定的宿主，内部不得运行任何 CPU 轮询循环，保持纯被动监听状态。


---

## ADR-0009 · 2026-07-06 · accepted
**决策**：KC 版本发布控制采用三层可见性：`canary`、`public_rollout`、`released`。GM 的个人 Me 页只负责本 GM 设备在 Canary/Released 间切换检查目标；普通用户只看到原本的版本区域。GM 控制台的 canary 区只保留两个动作：`Public` 是可开关的临时公开手动检查入口；`Released` 是一次性 promote，正式把当前 canary 转为 released 并通知落后用户更新。
**理由**：把“GM 自己测试哪个渠道”和“对用户开放/正式上线”混在同一个管理列表会导致操作语义混乱。成熟发布控制需要区分 internal test、manual public exposure、official release notification，且普通用户不应看到 canary/released 概念。
**影响**：`app_versions.public_rollout` 控制普通用户手动检查能否发现 canary；自动 update banner 和 update notification action 永远只读取 `released`。`release:canary` / `sync-app-version` 默认写入 private canary (`public_rollout=false`)。任何 IDE 不得用 iteration branch 或 GM 页面 channel selector 替代该模型。
**追溯**：人类在 2026-07-06 指出 GM/版本界面混乱，并明确要求 Public toggle 与 Released trigger 的语义。

---

## ADR-0010 · 2026-07-13 · accepted
**决策**：Brain-global 采用 [[Model Routing Guideline]]。M0–M3 按风险使用最低够用模型与跨 provider 审查；M4 项目定义级策划强制 OpenAI、Anthropic、Google 各自当前官方发布且本机真实可运行的最强模型完成 blind position、reciprocal challenge、3/3 ratification，才可标记 `M4 consensus candidate`。具体型号属于 dated appendix，不写死于 ADR。Agent 间允许使用可还原、可审计的机器优先 AWF；对人报告必须展开为其主要交流语言。Human 仍是唯一 acceptor；dissent 必须上报，AI 共识不等于 accepted。
**理由**：实际 KC/Brain 协作暴露模型映射过时、frontier 滥用、重复上下文、provider 偏见与审查证据不一致。真实三强 council 已对协议正文及 AWF delta 各自 3/3 approve、0 blocker；模型分级与 delta-only evidence 能同时守住最高层独立性和日常 token 成本。
**影响**：允许将 proposal 转为 live guideline，更新 [[SDLC Unified Workflow]]、[[Coordination]]、[[IDE Adapter Patterns]]、[[Shared Skill Registry]]、thin bridges、模板与 deterministic receipt checker。M4 缺席/fallback/receipt 不符只能输出 dissent/degraded packet，不得冒称共识。型号刷新须官方来源 + 本机 callability receipt。
**追溯**：人类 2026-07-13 明确要求更新 Obsidian 协议并立即用该方法审查 KC UX/UI 与 code；review 见 [[Model Routing Guideline Review]]。

---

## ADR-0011 · 2026-07-13 · accepted
**决策**：接受 [[KC UXUI Code Audit Council 2026-07-13]] 的 F1/F2 安全底座方向并进入实现。F1 将“可作为 safety activity truth 的信号”限制为已安装/原生运行面（Android APK、installed PWA、Tauri EXE/MSI）、用户明确手动确认及个人 Shortcut/native token integration；普通浏览器 tab 的打开、focus、pointer interaction 不是 passive safety evidence，不得写入 `behavior_pings`。定时确认完成必须查询 `behavior_pings` 的真实活动时间，不得查询 `device_state.last_heartbeat_at`。F2 要求全局 fetch→XHR fallback 只重试安全/显式幂等请求并完整传播 `AbortSignal`；push queue 采用 DB 原子 claim/lease、瞬时失败可重试、并发不重复发送、成功/无目标终态/重试失败可区分的投递状态。
**理由**：KC 的核心价值是低打扰但可信的“TA 可能没事”。普通网页或纯在线 heartbeat 会制造虚假安全；非幂等网络重放与 lossy/racy push 会在最需要可信时造成重复写入、漏推或重复通知。Sol、Fable、Gemini 已分别核验证据并对 F1–F4 方向 3/3 ratify；人类随后明确指示“处理吧”，构成本条 accepted gate。
**影响**：允许新增 append-only migration、信号资格 pure contract/测试、`resilientFetch` 安全限制、push-dispatch claim/outcome helper 及对应 Edge Function 修改。不得编辑旧 migration；`behavior_pings` 仍是唯一活动真相，`device_state` 继续仅作缓存；无 push target 的终态保留为明确产品政策，不冒充成功投递。F3 onboarding 与 F4 provenance/sleep 不包含在本批，另行实现与验证。
**追溯**：[[KC UXUI Code Audit 2026-07-13]] KCA-27..29；[[Model Routing Guideline]]；人类 2026-07-13 对 F1/F2 正式 ADR 下一步回复“处理吧”。

---

## ADR-0012 · 2026-07-13 · accepted · scope=Brain-global
**决策**：接受 [[Execution Collaboration Overlay]] v1，SHA-256 `510F911C29BEA2C3E10A68DA8F3CE7469AC6BD0233F751C444BDF2EBE75479A3`，并将其作为所有 Brain-governed 项目的通用 AI Collaboration Framework 执行层。M0–M3 在风险模型路由之外增加 `S/W/X` mutation route：默认单 owner；只有写集可隔离、验收可独立、无 worker 间依赖且收益类型明确时才拆分；最多三个 mutation worker、最多两家 implementation provider，第三家保留为独立 auditor；单一 integrator 顺序 fan-in。每次真实调用、route、artifact、gate、返工及 token/usage 都必须可追溯。
**理由**：ADR-0010 解决了策划与审查层的三公司独立性，但 KC F1/F2 实践证明，accepted multi-provider design 仍可能在修改阶段退化成未回执的单一宿主实现。Sol、Fable、Gemini 已通过 blind position、reciprocal challenge、同一候选哈希 Round C 复核并 3/3 approve；人类明确要求该框架是 General、正式设为协议，并以 KC 验证实际效益。
**影响**：更新 [[Model Routing Guideline]]、[[SDLC Unified Workflow]]、[[IDE Adapter Patterns]]、[[Shared Skill Registry]]、Executor/Auditor/Task Inventory/Evidence/Audit 资产及 `model-routing-check.mjs`。任何 IDE 不得把“在同一聊天里提到另两家”当成多公司执行；必须有真实 CLI/provider/model receipt。旧的重叠且未回执修改不得事后认领，须隔离、hash、重新分配并由合格 owner 采纳/重写/验证。框架不授予 merge、release 或 deploy 权限。
**追溯**：[[Execution Collaboration Overlay Council 2026-07-13]]；人类 2026-07-13 明确回复“这应该是一个 General 的 AI Collaboration Framework…确定了就设置协议吧”。

---

## ADR-0013 · 2026-07-14 · accepted · scope=Brain-global
**决策**：接受 [[Model Routing Guideline]] / [[SDLC Unified Workflow]] v2.7 token-economy correction。三家公司 top model 只在 M4 项目定义级策划同时出现；M4 accepted 后的修改重新分为 M0–M3，默认一个 cheapest-fit mutation owner + deterministic verification + 一次 integrated-diff cross-provider audit。M3 默认使用经同类 eval 证明够用的 daily-main High，只有明确 blocker 才升级对应节点到 provider top。`X` 不再接受 `risk-separation` 作为多 writer 理由，必须证明 `latency|specialism` 收益大于 coordination cost。所有 M2/M3 route 锁 model-call/tool-round/gross/fresh-input budget；soft checkpoint，hard stop/re-route，第二 repair 或超额预算须 human override。
**理由**：KC F1/F2 首次执行实验表明旧 route 虽阻止错误 fan-in，却把 M3 错配为两个 frontier writer + 第三家 audit；单次 Sol implementation 达 4,064,149 gross token，其中 95.93% input 为 repeated cached context，另有多次 rejected/unavailable calls。旧 `X/risk-separation` route 的组件实际共享 provenance interface，parallelism 没有节省时间，反而制造返工。
**影响**：协议升 active v2.7；Execution Route Card/checker 使用 schema v2，拒绝 M4 mutation、standalone frontier preflight、无成本证明的 X、未 checkpoint 的 token soft crossing 与 hard-limit continuation。历史 route `KC-F1F2-X-001` 保持 blocked evidence，不得继续或冒充合规；KC 后续须开新 `S` route。该修正不取消必要的跨 provider 独立 audit，也不授予 merge/deploy/release 权限。
**追溯**：人类 2026-07-14 明确要求先查明异常 token 消耗，并指示“改正协作系统；处理好后，再对 KC 的未完成修正继续做判断”。

---

## ADR-0014 · 2026-07-14 · accepted · scope=Brain-global
**决策**：接受 [[Provider Balanced Routing Candidate 2026-07-14]]（SHA-256 `93A992EB9CC007594BC612B111A062EF2E3893730267A83057F4ACA242E2B21D`），将 [[Model Routing Guideline]] / [[SDLC Unified Workflow]] 升至 v2.8。M1–M3 在 model tier 之前先按 capability、risk floor、dated outcome、tools/context/retention、quota/health 选择 provider；当前 IDE/host 不自动成为 owner。普通 coding/execution 使用 fast/low 或 daily-main；top 仅限 M4、项目级 plan/dispatch、困难 audit 或 evidenced escalation。相同 capability 的最近 10 个 accepted ordinary owner 参与 anti-concentration；存在相近健康替代时，同 provider 不得拿第三个连续 owner，除非有受限且可过期的 evidence override。
**理由**：v2.7 修正了多 frontier/多 writer 造成的 token 浪费，却没有修正 host bias；`cheapest-fit` 实际仍常退化为 Codex host 自己完成普通执行。表面 ledger provider 总数接近，不代表 ordinary ownership 平衡，因为 Anthropic/Google 多数记录来自 M4 council 或失败实验。三家 top CLI 对同一 neutral packet 完成 blind/challenge/ratification，最终 3/3 approve、0 blocker。
**影响**：Execution Route 升 schema v3；M1–M3 route/usage receipt 新增 capability、eligible/excluded、host/owner/reviewer、rolling count、winner/override 与真实非 host CLI evidence。M0 semantic deterministic task 不为 diversity 另开 CLI，也不计 provider ownership；M4 council 不污染 ordinary share。Provider affinity 只是 90 天可衰减 prior，不是永久领地。该 ADR 不要求平均配额，不扩大多模型节点，也不授予 merge/deploy/release 权限。
**追溯**：[[Provider Balanced Routing Council 2026-07-14]]；人类 2026-07-14 指出 CLI 不是只让 Codex 消耗 token，并明确要求高级模型负责策划/调度/审核、普通模型负责 coding/执行，且按三家公司各模型强项分配、避免集中。

---

## ADR-0015 · 2026-07-14 · accepted
**决策**：KCA-15/16/17 采用「先遏制」方向：①Scan2Sync 未绑定会话转移 → 禁用/收紧入口；②紧急信息 reveal 与加密实现不匹配 → 标注不可用并阻断误导性入口；③GM 永久删除错 schema/无鉴权 → 堵住越权路径。三项各为 M3/S 窄任务,不动替代架构;替代方案后续各自单独 ADR。**遏制落地前冻结公开发版**(Gate 1)。
**理由**：三洞的产品安全风险不低于 F1/F2;窄遏制当天可完,先止血再重建。
**影响**：允许 append-only 迁移/入口禁用/权限修补;不得顺手重构。发版解冻条件=三项遏制 verified。
**追溯**：[[KC Unfinished Repairs Reassessment 2026-07-14]] Gate 1;人类 2026-07-14 对 D1-D5 清单回复「好,赞成,执行」。

---

## ADR-0016 · 2026-07-14 · accepted
**决策**：睡眠窗采用**墙钟真相**:用户输入的数字(如 23:00–07:00)在任何时区变化后保持不变;timezone 仅作为解释当前本地时刻的元数据。新增 append-only 迁移安全转换存量 UTC 行;前端移除 UTC 换算;服务端以本地 now 对比存储数字。**每日报平安任务时间语义同选墙钟**(跟随当地时钟,KCA-20 选项 a),不静默继承、独立实现。
**理由**：现行"存 UTC 时刻"在换时区后数字漂移,违背用户直觉与 KC 原则 #3;墙钟模型与人的作息心智一致。
**影响**：`KC-F4-TIME-S-006` 解锁;迁移须版本化转换、可回滚叙事;[[Sleep Window]] 真相笔记随实现更新。
**追溯**：同上;audit F4 finding。

---

## ADR-0017 · 2026-07-14 · accepted
**决策**：F3 可执行 Onboarding 按 `KC-F3-SETUP-S-005` spec 方向实施:普通浏览器=只读+安装建议,禁止宣称"后台守护已就绪";每个设置项=动作→确切系统步骤→返回检查点→检测状态→测试 ping/服务器回执→恢复/降级态;"就绪"必须门控。iOS 更名"打开快捷指令设置",导入与自动化为两个设备本地步骤,仅保留可验证触发(充电/App/闹钟),删除解锁宣称。附带修:focus/pageshow 监听清理、Windows Web 设备误标、全局 onboarding 完成键、SOS 当签到的文案。
**理由**：Onboarding 不得在未解决的 F1/F2 真相之上谎报就绪;能力驱动的状态才是诚实 UX(P5/P8)。
**影响**：`KC-F3-SETUP-S-005` 解锁(排在 F1/F2 遏制之后)。
**追溯**：同上;三厂 3/3 ratified 方向。

---

## ADR-0018 · 2026-07-14 · accepted · scope=Brain-global
**决策**：Route 预算的 call 计数按**逻辑 call** 统计:同一逻辑任务因 CLI 权限弹窗重试、max-turns 续跑而产生的连续物理调用计为一次逻辑 call;全部物理调用仍逐条入 usage ledger 可查。硬停条件改为逻辑 call 超限或 gross/fresh token 超限。
**理由**：`KC-F2-NET-S-003` 代码全绿却因 4 次物理 call(含权限重试)超 M2 3-call 上限被硬停;权限重试非返工,按物理计数惩罚的是环境摩擦而非模型浪费,反而诱发弃件重做、违背 token 经济。
**影响**：[[Model Routing Guideline]] 计数条款随本条更新;checker 语义对齐。**一次性 override(随本条生效)**:保全 artifact `codex/kc-f2-net-s003@bdf10b5` 获准打捞——由 Google(agy)补做一次 integrated-diff 审计,通过即 fan-in main;OpenAI 自 2026-07-14 起因 quota 记为 ineligible(dated 事实,非永久);余队 owner 重排=Claude:F1-S-002/F2-PUSH-S-004/F4-TIME-S-006;agy:F3-SETUP-S-005/F4-PROVENANCE-S-007/KCA 遏制三件/视觉矩阵;互为对方唯一审计。
**追溯**：人类 2026-07-14 对 D1-D5 回复「好,赞成,执行」;board 14:26 S-003 blocked 记录。

---

## ADR-0019 · 2026-07-15 · accepted
**决策**：KC 剩余修复队列(`F1-S-002`、`F2-PUSH-S-004`、`F4-TIME-S-006`、`F4-PROVENANCE-S-007`、`F3-SETUP-S-005` 及后续 KCA/视觉)的执行分工改为:**agy(Google)为唯一 implementation owner/author,Claude(Anthropic)为 orchestrator + 唯一 cross-provider reviewer/auditor**。Claude 出契约级 S-route 规格包(WHAT:契约/文件范围/约束/验收/已核实事实),不写实现(HOW);agy 只在隔离 worktree 内写文件;**所有验证(typecheck/test/build/SQL 分支验证)由 Claude 亲跑**,agy 不需要也不获授运行任意命令的权限;Claude 对照契约审 diff,通过才 fan-in main。此条**取代 ADR-0018 的 owner 分派**(那条把 F1/F2-PUSH/F4-TIME 派给 Claude 写)。author≠reviewer 跨厂独立仍满足(Google 写 / Anthropic 审)。
**理由**：人类 2026-07-15 明确指示「都做,但我需要你去指示 agy 写,而不是自己写,你来调度、引导、agy 写、你来审核」。此前 Claude 曾单方面把遏制批改为「Claude 写/agy 审」(理由:agy CLI 写码笨拙),人类否决——要 agy 承担写码,Claude 专任调度与审核。这也更贴合 ADR-0014「host 不自动成为 owner」与真正的跨厂独立。
**影响**：ADR-0018 的 owner 表作废,改用本条;OpenAI 仍因 quota ineligible(dated)。**安全边界**:agy 以「仅自动接受文件编辑」的受限模式在隔离 worktree 内工作,不启用「跳过一切权限」的无人值守自动模式;审阅前不 fan-in;不授予 agy 直接 merge/deploy/release。高风险项须先有 accepted ADR(F1/F2=0011、F4-TIME=0016、F3=0017 均已 accepted;F4-PROVENANCE 为 M2/Standard 无需 ADR)。usage ledger 逐条记 agy 真实 CLI receipt。
**追溯**：人类 2026-07-15 指令;承 [[Model Routing Guideline]] ADR-0014/0018。

---

## ADR-0020 · 2026-07-18 · accepted
**决策**：SOS 触发不得等待定位。客户端先且仅调用一次无参数 `raise_sos()`，立即启动现有推送分发；定位异步完成后，只可通过新增的 `update_sos_location(_lat, _lng)` 补写该登录用户**自己当前仍为 open 且 cause='sos' 的告警**。该 RPC 只更新 `alerts.sos_lat/sos_lng/updated_at`，不得创建/升级告警、写 `alert_events`、改 stage/deadline/paused 状态、生成通知或触发推送；坐标须为有限数且在合法经纬度范围内。无匹配 open SOS 时不借用其他告警、不跨账户写入，返回未更新结果。迁移只新增，不修改旧 migration。
**理由**：现有两参数 `raise_sos` 将坐标与告警升级/通知副作用绑定；等待 GPS 会延迟安全告警，再调用一次则会重复升级/通知。现有 `saveSOSLocation` 写入 `emergency_info`，不是响应者地图使用的 `alerts.sos_lat/sos_lng`，不能代替受限补写 RPC。
**影响**：解锁新的 M3 SOS 修复路线；Claude/Anthropic 负责契约、亲自验证与独立审计，agy/Google 是唯一测试与实现作者，沿用 ADR-0019。先观察定位悬挂的 RED，再实现“告警/推送不等定位、只 raise 一次、晚到坐标尽力补写”。本条只授权本地实现与验证，不授权 commit、push、deploy、release、版本提升或生产数据库变更。
**追溯**：人类在 2026-07-18 先答复“让gm可试用”，随后明确“继续”；这是对 2026-07-18 SOS 受限晚到定位 RPC 提案的接受，并要求推进至 GM 可试用状态。

---

## ADR-0021 · 2026-07-19 · accepted
**决策**：接受 [[KC Routine AI Emergency Containment]] 的四道门修复。Gate 1 先止血：以服务端 `received_at`/`ingest_version=2` 建立活动安全真相，所有写入经同一受控例程，撤销 `behavior_pings` 直接插入与公开 initializer，稳定 `event_id` 保证幂等，≤100 条的认证批量 RPC 在单事务内返回逐项结果，离线/历史事件不得刷新安全状态；PWA 每个 runtime 只保留一个前台采集者，本地信号按用户分区，历史无主数据隔离；冻结随机/重复污染的旧画像，恢复确定性阈值过渡及可执行 daily cron；Gate 1 同时从 Home 隐藏本地-only `SafeAwayBar`，现有 `safe_window` 文案必须明确“只是本地计划，服务器监控仍在运行”。Gate 2 再完成服务端 quiet period、POST-only scoped credential 与客户端迁移，并在兼容窗口结束后拒绝 GET。Gate 3 从 canonical evidence 生成带来源、样本量、置信度与新鲜度的 shadow model；外部 AI 仅在明确同意后接收去标识聚合数据，只能解释或建议候选，不能直接控制告警。Gate 4 须有至少 14 个完整本地日的 shadow 证据、回放比较、无 P0/P1、独立检查和人类明确 `promote learned thresholds`，才可启用学习阈值。
**理由**：生产实测显示 cron/聚合、跨账户本地数据、匿名 `SECURITY DEFINER` initializer、URL credential、客户端时间、重复采集、Safe Away 权威性及 AI consent/activation 均存在 P0 级真相与安全缺口；当前作息画像和阈值不能继续被当作可靠安全依据。Claude 在独立方案检查中要求并确认两项必要修正：Gate 1 立即纠正 Safe Away 误导，离线同步采用有界批量契约而非 100 次串行 RPC。
**检查者规则**：本 ADR 及其后续 Gate 的最终独立检查只可由 **Codex/OpenAI 或 Claude/Anthropic** 签署，且检查者不得与受检 patch 的作者同席。**Gemini/Google 可参与讨论或承担有界编码工作，但其 verdict 不构成最终 inspection gate。**
**影响**：允许按 Gate 1→4 建立新的 High-risk 路线，使用 append-only migration、TDD、隔离 worktree、非生产 Supabase 与 canary 验证。旧 ping/aggregate/profile 只从 runtime 隔离，不删除、不静默归属；生产 promotion、破坏性历史清理与 Gate 4 激活均未获本条自动授权，须满足各自 release gate。若出现跨账户行、未同意的外部 AI 调用、客户端时间清警、GET/unsigned ping、migration drift 或 canary 告警回归，立即停止/回滚。
**追溯**：人类 2026-07-19 对方案回复“继续”，随后明确“检查者应由 Codex 或 Claude 负责，Gemini 只负责参与讨论或直接负责执行编码”；Claude Sonnet 5 对修正后的同一方案返回 `PASS`，无 blocker。详细边界、文件清单与验证命令见 [[KC Routine AI Emergency Containment]]。

---

## ADR-0022 · 2026-07-19 · accepted
**决策**：纠正 ADR-0021 Gate 1 的 sensitivity 回归。learned/profile 数据继续隔离，不重新取得 live safety 权威；Gate 1 使用一个确定性 neutral base `1.5h`，用户工具严格按已显示的增量解释：`high/sensitive = base + 0m = 1.5h`、`balanced = base + 45m = 2.25h`、`low/relaxed = base + 90m = 3h`。这取代 ADR-0021 D4 中错误写成绝对 `1.5h / 3h / 6h` 的三档值。由于新值相对已部署 Gate 1 只保持或收紧、不会扩大任何阈值，本次允许作为回归纠正立即恢复契约；不得借此重新启用污染画像或 learned threshold。

**影响检查门**：以后修改 KC 的告警、作息、Profile 或 sensitivity 前，执行者必须先读取相关 Project truth 与运行时资料，至少核对：`profiles` / `user_settings` / `user_activity_profiles` 的含义与 consent/profile quarantine，`private.silence_threshold` 的全部消费者，睡眠窗独立 gate，Routine 当前用户显示，以及 Watch/Group/GM 活跃状态的阈值字段。修复必须说明哪些表/函数/UI 会受影响、哪些明确不受影响，并用失败测试覆盖用户可见契约与安全不变量。

**验证与发布**：只允许 append-only migration；先 RED 再 GREEN；真实数据库角色/函数行为、前端契约、告警/睡眠/Group/GM 回归都要验证。最终独立检查仍只能由非作者席位的 Codex 或 Claude 签署；Gemini 可讨论或编码，不能签最终 gate。沿用现有 main-backed authenticated PWA，不创建无法登录的 Preview；默认 US$0 incremental spend。

**理由**：生产与代码只读核对证明，UI 仍承诺 `+0m/+45m/+90m`，服务端却被改成绝对 `1.5h/3h/6h`，并遗漏 D4 的过渡保护；这使 sensitivity 的实际跳幅远大于用户设置。人类在收到根因与最小修复说明后明确回复“那就修”，并补充要求每次修正先从 Project、Profile 等资料评估关联功能，构成本条接受与长期检查门。

**追溯**：[[Alert System]]、[[Usual Behavior Model]]；`KC-ALERT-THRESHOLD-REGRESSION-DIAG-001` 只读生产证据；人类 2026-07-19 当前指令。

---

## ADR-0023 · 2026-07-25 · accepted
**决策**：接受自适应告警判断架构，并先实施历史回放与无通知 shadow 验证。Routine mode 以当前用户可见的三个值为 canonical taxonomy：`regular_9to5`、`semester_break`、`shift_irregular`；旧/文档值只做兼容映射：`student → semester_break`、`shift_worker|flexible → shift_irregular`。不得重新启用旧 synthetic initializer 或把旧 raw-gap `user_activity_profiles` 直接恢复为 live authority。

首次本人告警的候选 neutral baseline 按严格层级解析：①可信、sessionized、排除已接受睡眠/quiet interval 的 comparable-context personal p95；② personal-global p95；③同 Routine mode 的 privacy-qualified cohort prior；④仅当群体先验缺失、过期、样本不足或校验失败时才使用 ADR-0022 deterministic threshold 作为 emergency failsafe。群体先验先计算每个合格贡献者的 neutral p95，再做 robust aggregate；禁止直接平均 raw ping/heartbeat、禁止高频设备按事件数放大权重。只有 `consent_data_sharing=true` 且 canonical evidence、coverage、跨度与质量合格的用户可贡献；任何用户均可读取发布后的非识别 aggregate prior。Sensitivity 仍是 baseline 之后的独立用户工具，shadow 阶段继续使用 `+0m/+45m/+90m`，不得污染 neutral model。

Configured sleep 是近似人类 prior，不是每天的事实。候选逻辑可用当晚可信本人活动延后 sleep start 或提前 wake；较晚 wake 只能由多晚 coverage-valid 的正向晚活动 pattern 提出 prospective、有界、缓慢的 compensation。当天持续缺席、离线、证据缺失或 Guardian 确认永远不能延长睡眠或暂停 effective-silence clock。Guardian 安全确认仍不是本人可信活动，不训练模型、不重置本人静默；本人可信活动仍缺失时保留既有 30 分钟 re-alert 状态机。

**Shadow / promotion boundary**：历史 replay 与 shadow 使用同一 versioned candidate evaluator。Replay 在既有 canonical evidence 上重算“若候选规则存在会怎样”；shadow 在实时 qualified evidence 上并行记录 would-have-decided threshold/deadline/basis/confidence，但不得创建、延迟、升级、解除或通知任何 alert。当前 ADR-0022 live path 保持不变。任何 personal/cohort/sleep compensation 获得 live authority 前，必须有单独的人类 accepted ADR，明确 per-sensitivity floor/hard ceiling、最大自动 sleep movement/update rate、paired safety metrics、最坏 segment/time-to-alert non-inferiority、rollout 和 rollback。

**隐私与失败边界**：只存 qualification、derived gap/interval、cohort support/quality、candidate decision provenance 与 aggregate evaluation 所需 metadata；不新增 location、contact content 或 message content。Coverage/ingestion uncertainty 不是 activity/sleep，不能延长 threshold/exclusion。群体样本低于 privacy support、贡献撤回、版本过期、漂移、时区/模式异常或 evaluator 不可 replay 时逐级 fall through；绝不把不确定性解释成“更安全，可以等更久”。

**影响**：授权 append-only schema、纯候选 evaluator、历史 replay、无通知 shadow recorder、aggregate-only report 与对应 TDD/非生产验证；不授权 deploy、production migration、cron enablement、release、canary 或 live promotion。实现必须先于任何 schema/runtime mutation完成 SDD/Spec/Task Inventory，并由非作者 Codex 或 Claude 做 integrated audit。若 shadow 路径产生通知/alert side effect、使用未授权贡献、泄漏 user-level cohort data、Guardian 被当作本人活动、absence 延长睡眠、或 deterministic live path 发生变化，立即停止并回滚 shadow writer/cron。

**理由**：用户指出 Routine mode 的产品目的本就是通过多用户选择与积累形成新用户合理起始基准，较固定档位更符合实际。代码核对证明 UI/copy/consent 已表达这一目标，但现有三个模式仍是 hard-coded templates，跨用户学习尚未实现；Gate 1 已正确隔离 synthetic initializer、raw heartbeat gaps 与旧 learned profile。生产可信 v2 诊断同时证明固定档位对多名用户过短，且清晨告警会累计睡眠墙钟时间。采用 cohort prior 能恢复原产品意图，但必须在不放大单用户、隐私最小化和无 live side effect 的前提下先验证。

**追溯**：人类 2026-07-25 明确接受“按三个模式＋回放/影子验证继续”；[[KC Adaptive Alert Judgment Model]]；`KC-ALERT-RHYTHM-DIAG-001`；`KC-ALERT-JUDGMENT-M4-001`（degraded council，未伪称 M4 consensus）；[[Alert System]]、[[Sleep Window]]、[[Usual Behavior Model]]。

---

## ADR-0024 · 2026-07-25 · accepted

**决策**：采用版本化、hash-pinned、fail-closed 的本地/CI migration replay compatibility harness，作为不可修改的生产迁移历史与可复现数据库验证之间的显式兼容层。所有仓库旧 migration 必须逐字节保持不变；harness 只可在 disposable local database 中注入已知 synthetic `auth.users` fixture，并只在隔离的临时 migration copy 中纠正 `20260624140000_adaptive_routine_impl.sql` 的已知非法 `</loop>` token。执行兼容动作前必须核对两份已知旧 migration 的精确 hash；hash、目标或替换数量不符时立即失败，不得猜测或继续。

**权限边界**：harness 只属于测试基础设施。不得连接 linked/production Supabase，不得 push/repair/rewrite/squash/mark-applied 远端 migration history，不得创建生产用户或管理员，不得修改旧 migration，不得改变 ADR-0022 live threshold、`process_escalations`、Guardian 30 分钟状态机、alert/notification、cron、deploy、release 或 learned live promotion。临时副本和 fixture 不得进入生产 artifact；任何新增的历史 replay 缺陷必须 fail closed 并重新交由人类裁决。

**验证语义**：通过 harness 只能证明“版本化兼容回放路径可复现”，不能声称 untouched historical chain 已经干净。验证证据必须包含旧文件 hash、精确兼容动作、完整 migration/pgTAP 结果与 tracked historical files 未变化。后续若要重写或 squash production history，必须另立 human-accepted ADR 并核对生产 migration history。

**理由**：官方本地 Podman/Supabase runtime 已验证健康；fresh replay 依次暴露固定管理员 FK 依赖和旧 PL/pgSQL 非法 token。常规 seed 在 project migrations 之后执行，新 append-only migration 也无法越过先前语法失败。Brain 同时记录后续 Gate 1 migration 已上线生产，因此改写旧文件会制造生产与仓库历史漂移。显式、一次性、hash 固定的兼容回放比改写历史或维护第二份长期 schema snapshot 更窄且可审计。

**追溯**：人类 2026-07-25 对兼容回放基线方案明确回复“接受”；[[KC Migration Replay Compatibility Baseline]]；`KC-LOCAL-SUPABASE-BASELINE-001`；`KC-ADAPTIVE-ALERT-SHADOW-IMPL-001`；[[Security Privacy Baseline]]。

---

## ADR-0024 amendment · 2026-07-26 · accepted

**决策**：在 ADR-0024 已授权的本地/CI replay compatibility harness 中，新增且仅新增两个 hash-pinned 的临时副本 BOM 兼容动作：

- `20260625174615_sync_activity_truth.sql`，SHA-256 `0c92784730710fe1b487c01f8199115f1fc7053238e4607c52428e2cb45a2090`
- `20260626072619_scoped_group_activity_views.sql`，SHA-256 `bca5cd87009bba29e5906487322af56ca99c30db1d9717113886f347dbec85ff`

只有文件名与 hash 同时完全匹配、源文件开头恰好存在一个 `EF BB BF` 时，harness 才可在隔离临时副本中删除这三个开头字节；输出必须逐字节等于 `source.subarray(3)`。这不是通用 BOM/编码清理授权。

**失败边界**：缺少 BOM、双 BOM、BOM 不在 byte 0、hash 漂移、额外替换、额外 BOM migration、未知编码、源文件前后 hash 改变、完整临时树出现未授权差异、manifest 缺失或临时路径经 symlink/junction 逃逸时全部 fail closed。完整树只允许既有 synthetic fixture、已接受的 `</loop>` 临时副本修正和本条两个 BOM 临时副本修正。任何第四类历史缺陷必须重新交由人类裁决。

**权限边界**：仓库历史 migration 必须逐字节不变；不得连接或修改生产、远端 migration history、告警/Guardian/通知、cron、deploy、release 或 live promotion。真实 replay 与 pgTAP 通过后仍只证明兼容回放路径可复现，不证明 untouched history 干净。

**理由**：真实回放证明前两项兼容动作有效后，在首个 BOM migration 处按 ADR-0024 正确停止；独立检查确认 65 个 migration 中只有上述两个带 leading BOM，且两者均已有 live-application 记录。Append-only migration 无法越过更早的 parser failure，修改旧文件则制造生产历史漂移；对两个精确 hash 的临时副本各删除一个固定三字节前缀，是最窄、可审计且可回滚的解阻方式。

**追溯**：人类 2026-07-26 对 BOM 兼容补充明确回复“接受”；[[KC Migration Replay Compatibility Baseline]]；`KC-MIGRATION-REPLAY-COMPAT-IMPL-001`；独立 gpt-5.6-sol BOM compatibility review。

---

## ADR-0027 · 2026-07-26 · accepted

**决策**：保持 `api.auto_expose_new_tables=false`，采用显式、逐表逐角色逐操作的最小权限 Data API ACL 基线。以一个新的 append-only migration 表达当前告警与 Routine 路径真正需要的权限，并继续用既有 RLS、窄 RPC 与服务端密钥边界约束数据可见性和写入能力。不得用平台旧默认、临时测试 GRANT、`GRANT ALL`、`PUBLIC`、blanket `anon` 或改用 `postgres` 测试身份来掩盖 fresh deployment 的授权缺口。

**当前最小契约**：实现前必须逐项核对直接调用者与 RLS，并仅授予已证明的操作：`authenticated` 对 `behavior_pings` 只读且 own-row，写入继续 RPC-only；`service_role` 对 `behavior_pings` 只读；Routine worker 所需的 `heartbeat_tokens`、`user_settings`、`daily_activity_aggregates`、`user_activity_profiles` 只给实际读取/有界 upsert 权限；告警/通知/任务链的 `alerts`、`notifications`、`checkin_tasks` 及必要的 `profiles`/`clients` supporting reads 只给当前 caller 需要的操作。`PUBLIC` 与 `anon` 不新增安全/Routine 表权限，scheduler/private helper 不向客户端开放。

**实现与验证**：只授权本地实现与非生产验证。必须使用新 migration，先写 RED pgTAP，再验证 catalog ACL 与真实角色行为：authenticated owner access、跨用户拒绝、`behavior_pings` direct write 拒绝、service worker reads、notification recipient isolation、scheduler denial；随后执行 ADR-0024 全量 fresh replay、完整 pgTAP、typecheck/tests 与非作者独立安全审计。发现额外对象时必须补 caller/RLS 证据和精确权限，不能改成 wildcard。

**权限边界**：本 ADR 不改变 ADR-0022 live threshold、Guardian 30 分钟状态机、alert/notification lifecycle、cron、adaptive shadow/live authority、生产数据、deploy 或 release。生产应用该 migration 需要在精确 diff 与审计证据就绪后另行取得人类授权。RPC-only read architecture 保留为未来可选的更大安全重构，不作为本次回放解阻。

**理由**：Supabase 当前新项目默认不再自动向 Data API 角色授予新表权限；本地 fresh reset 的 catalog 与 pgTAP 证明 `service_role`/`authenticated` 缺少当前客户端和 Edge Function 直接访问所需的表级 ACL。`BYPASSRLS` 不能替代表权限，测试 shim 只会隐藏灾备、CI 与新环境无法复现生产授权状态的真实缺陷。显式最小权限 migration 是当前架构下最窄、可测试、可恢复的根因修复层。

**追溯**：人类 2026-07-26 对推荐的 Option A 明确回复“接受”；[[KC Explicit Data API ACL Baseline]]；`KC-MIGRATION-REPLAY-COMPAT-IMPL-001`；独立 gpt-5.6-sol 根因诊断与 gpt-5.6-terra ACL contract audit；[[Security Privacy Baseline]]。

---

## ADR-0028 · 2026-07-27 · accepted

**决策**：接受 `SPEC-KC-ADAPTIVE-SHADOW-PROD-001` 的生产影子设计。建立与 `process_escalations()` 完全独立的私有自适应告警影子管线，每 5 分钟评估候选判断，但 ADR-0022 继续作为唯一 live authority；影子结果不得创建、更新、延迟、暂停、解决、升级或通知任何真实告警。

**覆盖与证据契约**：连续观察只能来自同一健康 Android/Tauri 采集器的成对、服务端接收、来源可识别 coverage lease；lease 不是 activity，不刷新 live liveness，不从缺失向未来填充。普通浏览器/PWA、单个 ping、`device_state`、`clients.last_seen_at`、手工 check-in、Shortcut、Guardian、缺席或 collector outage 都不得伪装成连续覆盖；缺失/不支持必须得到稳定的 `unknown/unreplayable` 结果。

**隐私与保留**：评估全部仍有至少一个 `group_members.monitored=true` 方向的活跃用户。个人候选可使用本人合格证据；只有当前 `consent_data_sharing=true` 的用户可贡献 cohort。个人/客户端可识别明细最多保留 35 天，长期只保留 contributor≥10 的 k-anonymous 去标识聚合；不向外部 AI 发送影子数据。

**运行与安全边界**：基础对象以 `enabled=false`、`accept_coverage_leases=false`、无 Cron 发布。手工 committed canary 必须用当前事务的 `pg_stat_xact_user_tables` 证明 `alerts/alert_events/notifications` 零 DML，并证明 live function hash、ACL、publication 和 scheduler absence 不变。只有该 canary 通过后，另一条 append-only activation migration 才可添加两个命名任务（5 分钟 cycle + 每日 maintenance）。超时、live write、hash/ACL/publication drift、输出畸形、隐私/consent 违规、异常增长立即关闭影子；一般失败连续三次关闭。停止影子不得改变 ADR-0022 live Cron/function。

**实施与委派**：实现属于 High-risk/M3，必须在隔离 worktree、append-only migrations、TDD 和精确 migration manifest 下进行。候选源只整合已审计 adaptive/replay 资产，排除未获本次授权的 ADR-0027 ACL migration，并保留已上线 group monitoring fix。充分规格化、隔离且机械可验的实现包可由 agy 在 Codex Manager 的 locked hash-addressed order 下执行；Claude 做非作者只读独立审计；双方不得自行补需求或再委派。

**发布边界**：本 ADR 只授权实施计划、本地实现、构建与审计准备，不授权 production migration、Cron activation、web/APK/Tauri publication 或 adaptive live promotion。生产基础部署、覆盖采集器发布、手工 canary、Cron activation 各需各自明确的 release/production gate。至少 14 个完整本地日的合格影子证据、≥99% cycle 成功率、p95<60s/max<120s、零安全/隐私违规及独立审计无 blocker，才允许另写 live-promotion proposal；任何不足都保持 ADR-0022 live。

**追溯**：人类在当前 Codex 任务中逐项同意无通知、5 分钟、35 天、monitored population、consent-gated cohort、两阶段启用和独立 DB Cron，并于 2026-07-27 明确要求“按我赞成的去处理”；`docs/superpowers/specs/2026-07-27-adaptive-alert-production-shadow-design.md`；[[KC Adaptive Alert Production Shadow]]；`KC-ADAPTIVE-SHADOW-PROD-SPEC-001`。

## ADR-0029 · 2026-07-29 · accepted

**决策**：接受 [[KC Evidence Admission and Gap Semantics]] 的证据准入与间隙语义修正。核心是纠正一条既有事实判断：**`ingest_version=1` 历史不是低质数据**。对 v1 数据量最大的三个用户做 `kind='app'` 相邻间隔分析，固定节拍占比仅 2–4%（30s 桶 3.5–4.2%，60s 桶 1.8–3.2%），即不规则的人类驱动事件，非机器心跳、非重复写入。v1 与 v2 的唯一实质差异是采样密度（v1 有 57.9–70.9% 的间隔 <2min，v2 为 7.2–8.1%），由 v2 的 5 分钟合并造成，属**单位不一致而非质量缺陷**；`sessionization.gap_minutes=30` 在测量任何间隙之前即已消除该差异。据此撤回先前"v1 低质/重复"的表述。

**P1 · v1 历史按 session 化纳入训练**：新增独立只读的规范化证据源，不修改 `behavior_pings` 原行，保留 `ingest_version` 原值并带独立 provenance 标记，可审计可回滚。v1 证据**仅供模型训练**，不得刷新 heartbeat、不得解除告警、不得满足 check-in —— ADR-0021 Gate 1 的 live-safety 边界完全保持。

**P2 · coverage 从渠道白名单改为间隙语义分级**：证据密度与准入资格当前完全倒置 —— ios-pwa 用户产出 76–1840 ping/天却永久不合格，android-apk 用户产出 6.1–11.5/天却是唯一合格来源；生产中 tauri 客户端为 0。原白名单的理由（只收能证明连续观测的平台）成立，但混淆了"能否为间隙背书"与"能否提供可用证据"。改为给间隙标注可观测性状态：`known_idle`（Android + Usage Access 已授权，全权重）、`unknown`（iOS PWA 等，计入但置信度打折）、`outage`（无采集器，排除）。

**P3 · 移除写入路径的 5 分钟合并**：合并的真实收益是写入量而非数据质量，当初以质量名义引入，副作用是造成 v1/v2 单位不一致。幂等由 `event_id` 保证；滥用应由速率限制处理（合并仍允许 288 次/天/源，对滥用几无作用）。高频源于发射端设计（`kind='interaction'` 1526 条/天来自绑在 touch/scroll 的 DOM 监听器），正确修法是在客户端收敛发射条件。若仍需控制写入量，改用显式速率上限并明确记为成本决策。

**P4 · 不做调整**：iOS 上 PWA 无法观测前台使用，该能力不对 Web 开放（DeviceActivity/FamilyControls、HealthKit 均需原生 app 与 Apple 审批）。人类 2026-07-29 决定**保留现状，不作任何调整**。提案中记录的 B 类方案（按间隙确定性调节 `stage='self'` 宽限，参考 Apple Check In 的"截止时间 + 用户确认"模式）仅作为备查，本 ADR 不授权实施。

**P5 · 学习进度 UI 改接真实证据（不下架）**：人类指出置信度 UI 本身是客制化学习的必要配合，原提案将其列为下架项属判断错误。

**事实更正（2026-07-29，实现前代码核查）**：先前多处声称"UI 仍在展示冻结于 2026-07-06 的 `model_confidence`，是在向用户承诺不存在的个性化"—— **该说法不成立，据此撤回**。全项目检索 `confidence` 在 `src/` 下仅命中 `database.types.ts`（表类型）、`usualModel.ts`（本地灵敏度模型，与服务端画像无关）及两个测试文件；`RoutineInsights.tsx` 虽调用 `my_routine_status`，其 state 类型只声明 `threshold_seconds`/`last_behavior_at`/`sleep_start`/`sleep_end`/`in_sleep_window`，**从未读取** `model_confidence`/`model_explanation`/`model_version`。RPC 仍返回这三个字段属契约冗余，且 `routineSafetyMigration.test.ts` 有断言依赖其存在，不构成用户可见的误导。

**真正的误导项**：`RoutineInsights` 的学习进度条与文案。`learnedDays` 由 `(now - installedAt)/DAY` 得出，仅统计注册后经过的日历天数，与证据积累完全无关；满 `config.learningDays`（14）天后显示 `routine.learn.done` = "已建立作息基线(满 {total} 天)"，而实际上没有任何基线被建立，也没有任何东西影响告警判定。这是用户真实可见的虚假承诺，是 P5 的首要修复目标。

**P5 修复范围**：(a) 进度与文案改接真实证据 —— 读当前 shadow version 下该用户的 `alert_gap_profiles` 的 `sample_count`/`distinct_support_dates`/`quality_state`/`confidence`，`low_support` 时诚实显示证据不足并说明当前使用通用阈值，未达成基线时不得显示"已建立作息基线"；(b) `my_routine_status` 的三个 model 字段改为由 `alert_gap_profiles` 供数或明确标注为已弃用，需同步调整 `routineSafetyMigration.test.ts` 的断言。

**下架清单**：`daily_activity_aggregates` 中 1,627 行早于建库日 2026-06-10 的 `random()` 合成种子（保留 273 行真实数据）；冻结的 `user_activity_profiles`；`update-routine-profile` edge function（对应 weekly cron 已于 Gate 1 移除，函数仍 ACTIVE）。

**权限边界**：本 ADR **不**改变 `private.silence_threshold`、**不**改变 ADR-0022 的 live authority、**不**请求 ADR-0021 Gate 4 提升。P1/P2 改变模型输入，必须先在 shadow 状态下产出对比证据。P3 触及 safety-critical 写入路径，需独立 TDD + pgTAP + 回放验证，与 P1/P2 分开落地。实施顺序：P5 → P3 → P1 → P2。

**已记录的执行偏差**：2026-07-29 由 Claude 执行的 ADR-0028 Phase 1 生产启用（注册 `alert_model_versions` `kc-shadow-prod-v1` = `958de976-7742-4fac-ba65-17983b5c6833`，并设 `enabled=true`/`accept_coverage_leases=true`，未排任何 cron）**未执行 ADR-0028 规定的手工 committed canary**，即未用当前事务的 `pg_stat_xact_user_tables` 证明 `alerts/alert_events/notifications` 零 DML。实际验证为前后计数与 hash 对比：live `silence_threshold` 定义 sha256 `686116ef…` 未变、`cron.job` 5 个且 adaptive 0 个、alerts 684 与 notifications 2362 未变、shadow decisions 0。此偏差在 Cron activation（Phase 2）前必须补做正式 canary。

**追溯**：人类 2026-07-29 就"让累积数据实际被使用"给出方向并选择 shadow-first 路径；随后明确指出 v1 质量判断有误、iOS PWA 才是高质量来源、5 分钟合并属多余设计，并回复"P1、2、3执行"、"P4 保留现状不作调整"、以及授予 Decisions.md 写入权限。[[KC Evidence Admission and Gap Semantics]]；`KC-ADAPTIVE-SHADOW-ACTIVATE-001`；`KC-ALERT-RHYTHM-DIAG-001`。

---

## ADR-0030 · 2026-07-29 · accepted

**决策**：明确 Keep Contact 多端正式上架与平台发版策略：
1. **Android 端**：以原生 APK/Capacitor 形式作为 **Google Play Store** 正式上架目标。所有原生前台服务（`specialUse`）、后台常驻、广播接收器（`Context.RECEIVER_EXPORTED`）、权限申请（`PACKAGE_USAGE_STATS` / `POST_NOTIFICATIONS`）、隐私政策（`/privacy`）、数据删除与注销（`/delete-account`）及 Play Console 申报声明均围绕 Play Store 审核合规准则进行设计与收敛。
2. **桌面端 (Windows / Linux)**：以 Tauri 桌面应用（MSI/MSIX/Flatpak/Snap/AppImage）形式作为 **Microsoft Store**（Windows）及 **Linux 软件应用商店**（Flathub / Snapcraft 等）正式上架目标。自启动、后台北斗/静音守护与后台轮询机制均围绕桌面商店合规进行准备。
3. **iOS 端**：因 iOS 系统后台沙盒与平台特有限制（如限制无感后台唤醒与传感器常驻），暂时保持 **iOS PWA (添加到主屏幕)** 为正式发版与监护形态，暂不进入 Apple App Store 上架管线。

**理由**：明确各平台的目标发版渠道（商店上架 vs PWA）是指导技术架构、敏感 API 使用、前后台服务声明以及权限审核合规准备的前置保障。Android 与桌面端需要面向正规 Store 做严格的合规收敛，而 iOS 保持 PWA 可在零审核摩擦下提供极致简便的锁屏/桌面无感守护体验。

**影响**：
- `Product Requirement.md` (REQ-KC-010) 更新目标渠道与上架准备定义。
- Android 原生层（取消假阳性 `ACTION_SCREEN_ON`、保持 `ACTION_USER_PRESENT` + `PACKAGE_USAGE_STATS`）、Google Play 合规文档（[[Google Play Store Compliance]]）、前台服务 `specialUse` 声明及全量注销/隐私路由保持 Store 合规就绪。
- GM 控制台及版本检测将 Web 普通浏览器会话排除在正式监控终端之外，仅将 iOS PWA、Android APK、Tauri Desktop App 作为官方检测对象。

**追溯**：人类于 2026-07-29 明确指示：“给 KC 的 Project 真实需求中，加入 APK 打算上架 Google Play 和 Tauri 桌面端打算上架 Microsoft Store 和 Linux Store，Apple Store 暂时保持 PWA 方式”。

---

## ADR-0031 · 2026-07-29 · accepted

**决策**：允许 GM 使用一个显式、可撤销、可设到期时间并记录原因的特殊权限，暂时抑制指定用户的**新** `silence` / `dark_device` 告警。此能力用于 GM 已知某位用户当前处境会造成不正确告警、继续告警反而尴尬或扰民的情况。只有 `private.is_admin(auth.uid())` 为真的已认证 GM 可调用 `gm_mute_user` / `gm_unmute_user`；普通 authenticated、anon 与直接表访问均不得取得该权限。

**窄边界**：Mute 只从 `process_escalations()` 的新告警候选中排除尚未到期的用户。它不得解决、暂停、降级、延迟或终止既有 open alert；既有告警按原有 `self → group → community → terminal` 状态机继续升级。到期或 GM 主动 unmute 后，新告警判断立即恢复。`private.silence_threshold`、睡眠窗、behavior ping 真相、Guardian 确认、Adaptive Shadow、Cron 与通知内容规则均不因 mute 改变。

**验证与发布**：使用 append-only `20260729180000_gm_mute_user.sql`；必须有真实角色 pgTAP 证明非 GM 拒绝、active mute 只抑制新告警、expired/unmute 恢复、既有告警继续升级、阈值 hash 不变，并更新此前把 `process_escalations()` 整体定义写死为绝对不变量的两条测试。生产应用仍属于 0.5.22 release gate，须经过 committed canary、完整 replay、独立 Claude/Codex 审计、回滚与 watch window。

**理由**：绝对禁止修改 live function 的旧测试早于 GM 特殊权限产品需求。把静音伪装成 monitoring-direction 变更、隐藏 trigger 或阈值放宽会污染用户真相并制造不透明裁决；在主裁决函数中加入一条可见、GM-only、按用户和期限限定的新告警排除，是更窄且可审计的实现。

**追溯**：人类 2026-07-29 明确接受该冲突裁决，并说明“这个功能的目的是用来暂时关闭一些情况尴尬的用户的不正确告警，所以需要有这个特殊权限”；`KC-GM-MUTE-AUTHORITY-001`；[[GM Alert Mute]]。

---

## ADR-0033 · 2026-07-30 · accepted

**决策**：确立 iOS Native App (Capacitor + Swift DeviceActivity 原生扩展) 免 Mac 自动化云端构建与 TestFlight 分发管线：
1. **免 Mac 自动化打包**：配置基于 GitHub Actions 的 macOS 云端构建工作流 (`.github/workflows/ios-testflight.yml`)。开发者无需购置物理 Mac 电脑，只需在 Windows/Linux 本地代码库中提交代码或触发 Action，云端使用 GitHub 预装 Xcode 与 Fastlane 工具链自动完成打包、证书注入与编译。
2. **高隐私被动存活扩展**：引入 iOS 官方 `DeviceActivity` (Screen Time) 原生 Swift 扩展组件 (`DeviceActivityMonitorExtension`)。由 iOS 系统在后台无感捕获用户屏幕操作事件（零敏感数据泄露、不接触 App 名称与内容），并向 Supabase 自动投递被动存活 Ping。
3. **TestFlight 90天长期分发与续期**：利用付费 Apple 开发者账号注册 TestFlight 测试通道。所有测试人员（家人/团队/种子用户）**无需**开发者账号且**零费用**，通过公开/内部邀请链接即可在 iPhone 上安装。每次云端出包自动打通 90 天循环续期能力。

**理由**：解耦了物理 Mac 硬件限制，彻底消除了早期测试需要频繁面对 App Store 审核的摩擦；同时在 iOS 端实现了超越传统 Web PWA 的高隐私、高品质原生被动守护。

**影响**：
- 新增架构规范文档 [[iOS Native TestFlight Pipeline]]。
- `Product Requirement.md` (REQ-KC-010) 与 `Keep Contact.md` (项目主页) 补充 iOS Native/TestFlight 路线与关联规范。
- 允许后续所有 AI / IDE 代理（Codex、Antigravity、Claude Code 等）读取 [[iOS Native TestFlight Pipeline]] 并共同推进工作流建立。

**追溯**：人类于 2026-07-30 明确准备好 Apple 开发者账号，并指定：“打算使用 GitHub 来处理 Xcode 打包（回避必须使用 Mac 的情况），最后用 TestFlight 实测。帮我把这个 iOS 原生的计划弄到 Obsidian 去，让别的 AI 也可以协助处理转换”。

---

## 相关
- [[Coordination]]
- [[Alert System]]
- [[Behavior Pings]]
- [[Usual Behavior Model]]
- [[Google Play Store Compliance]]
- [[iOS Native TestFlight Pipeline]]

---

## ADR-0032 · 2026-07-30 · accepted

**决策**：人类是产品与开发决策者，Obsidian 只记录事实，不能反向推翻人类已经明确的产品目标。有效旧记录必须立即作为个性化 live threshold 的起点，不得要求用户重新从 `1.5h / 2.25h / 3h` 固定模板开始累积。新 canonical-v2 记录继续在该起点上延展；当更新后的合格画像覆盖这些记录时，由新画像接替临时延展，不重置、不重复计数。

**安全方向**：个性化结果只允许把固定模板向后延长，绝不允许产生比既有固定模板更早的告警；无有效画像或画像为 `low_support/stale/invalid` 时才回退固定模板。阈值仍受 600 分钟硬上限约束。

**睡眠规则**：所有 `silence` 告警创建和自动解除统一使用 `private.sleep_relaxed`，即完整配置睡眠窗口加醒后两小时缓冲。`device_state.status='alert'` 只是描述状态，不再拥有绕过睡眠和 canonical silence 计算的独立告警权限。`dark_device` 的 18 小时硬安全线保持独立。

**追溯与上线**：人类 2026-07-30 明确纠正“从零/从模板重新开始”的实现方向，并要求减少每天的误报。append-only migration `use_history_seeded_live_threshold_and_sleep_grace` 已通过 20 个 pgTAP 文件 / 649 条断言并应用 production。旧 shadow pin 仅兼容这一个明确授权的 successor definition，未知 hash 继续 fail closed。`KC-HISTORY-LIVE-BASELINE-001`。

---

## ADR-0034 · 2026-08-01 · accepted

**决策**：ADR-0004「原生推送一律发空包」由**一刀切**改为**按通知种类分流**。

- `concern` 与 `self` 走 FCM/APNs **alert 推送**：包内携带标题与服务端已渲染的正文（含发起人显示名），由系统直接显示，锁屏可见、有提示音、App 被划出多任务后仍投递。
- `group`、`community`、`terminal`、`task_*` 及其余种类**维持空包 tickle**，正文仍由设备醒来后自行从 `notify-feed` 拉取。
- Web Push 一律不变（其包体本就以订阅方 `p256dh`/`auth` 端到端加密，推送服务读不到）。

**理由**：这两种通知是**当事人本人在告警升级到他人之前解除告警的唯一机会**。空信封自己无法显示任何内容，必须依赖 App 进程活着去渲染；而 iOS 上用户把 App 划出多任务后，后台推送根本不投递 —— 最该保证送达的一条反而成了最不可靠的一条。且这两种的正文只涉及当事人自己与发起关心者，不含任何第三方的处境信息。

**代价（精确范围）**：
- Apple / Google **新增可见**：某台设备收到一条「有人在关心你，请打开 App 报平安」级别的文案，以及发起人的显示名。
- **仍不可见**：住址、紧急联系人、告警级别、失联时长，以及整条升级链上任何通知的内容。
- **本就可见（非本次新增）**：该设备在该时刻收到过一条 KC 推送 —— 空包方案同样暴露这一点。

**配套去重**：alert 推送带 `tag = 通知行 id`；Android 端 `NotifyWorker` 改用同一 tag 发送，15 分钟兜底轮询若发现该行仍未读，重发会**替换**系统那条而非叠加；iOS 端 alert 推送不带 `content-available`（不唤醒 App 重复渲染），且 `NotifyFeed` 显式跳过这两种。Android 侧另在 `MainActivity` 启动时即创建 `kc_alerts` 高优先级渠道 —— 渠道不存在时系统会把推送降级为默认重要性，失去横幅与提示音。

**已知边界**：Android 用户在系统设置里执行「强行停止」后，至下次手动打开 App 前 FCM 一律不投递（平台限制，对所有 App 成立）；日常从最近任务列表划掉不属于此种情况。若日后要求连 `concern` 正文也不经 Apple，标准解法是 Notification Service Extension（显示前用本地渲染替换正文），需新增 Xcode target，不在本决策范围内。

**追溯**：人类 2026-08-01 报告「send concern 对方锁屏没有跳出通知」，排查见 `KC-PUSH-NATIVE-CHANNEL-REPAIR-001`。人类随后明确要求：「它应该要那种会和通知一样由系统直接显示、锁屏必亮、杀掉 App 也投递的类型，要有通知音效的那种。投递的内容可以只是 xxx 向你发来 concern 这种类型的内容」，并于同日以「修」授权本修订、以「你去」授权代为记录。提案见 [[KC Self-Addressed Alert Push Amendment]]，实施见 `KC-SELF-ALERT-PUSH-VISIBLE-001`。

---

## ADR-0035 · 2026-08-02 · accepted

**决策**：Routine 学习路径由「设备级、可审计、严格采纳」重构为「账户级、群体锚定、宽进统计」。三条原则由人类给出，是本决策的宪法：

1. **个人学习是对账户的学习，不是对设备的学习。** 同一账户在所有已登录设备上的告活记录汇总成单一时间流；设备只负责收集上报，统合与判断全在后台。
2. **Preset 是活的。** 同一 preset 下多个用户的告活数据在后台汇总，产出该类型参考模型并实时回填 preset 本身；模板不再是写死常数。
3. **不给弱信号加监工。** 要求设备证明「我当时在观测」，本质是对告活功能本身的不信任；正确做法是提升告活信号自身的质量（如实标注来源、触发方式、时钟偏差），而非外挂一套监测体系。

**不设异常值上界**：人类明确否决写死的间隔死线——用户可能确实极少使用设备，多设备同账户尤其如此，写死的线会误伤真实行为。稳健性改由**向 preset 群体模型收缩**提供：个人值与群体值按样本量加权（`权重 = n/(n+k)`），样本少时群体主导、样本多时个人主导。该机制同时天然实现了「记录不足先用模板、随后逐日微调收敛」，不存在跨过门槛的跳变。

**统计量**：保留 p95 作为基准。不上移至 p99——尾部分位数需要更多样本才估得准，小样本下 p99 近似等于最大值，反而会被单次掉线主导；稳健性由收缩机制承担，而非靠推高分位数。

**重算与收敛**：重算频率每日（沿用现有定时任务）；收敛速度由样本量常数 `k` 决定而非天数——不同用户产生数据的速率相差极大，按天数收敛等于对轻度用户拿噪声当规律。`k` 的取值须用生产库现有真实记录标定后提交人类确认。

**取消上限的连带效果**：600 分钟上限取消后，灵敏度三档缓冲（0/45/90 分钟）才真正体现在最终阈值上。此前「无论怎么调 sensitivity 阈值都是 10 小时」正是被该上限削平所致。

**代价（人类知情接受）**：
- 实时路径失去可重放审计能力；出问题只能从原始告活记录重算。影子评估体系保留但摘出实时路径，作为离线工具。
- 取消上限意味着告警可能显著延后（iOS tester 实测 p95 为 753 分钟）。**这是以漏报延迟换误报减少**，方向由人类明确选定。
- 改动对象是安全功能的判定依据，缺陷后果为「该响时没响」。因此实施必须先影子并行比对，差异可解释后方可切换。

**触发本决策的实测证据**（2026-08-02 生产库）：已收集告活记录 66,047 条 / 10 个用户 / 7 周连续；而实际被采纳进阈值计算的样本仅 2 条，Preset 群体模型产出 0 行。覆盖租约在整个产品生命周期内只有 `android-apk` 一个渠道、一个用户产生过，且已于 2026-07-31 因重装导致 UsageStats 权限重置而断供。iOS PWA（当前多数用户）因网页上报器首行 `if (!isTauri()) return` 而结构性不可能产生证据；iOS 原生无任何上报实现。

**追溯**：人类 2026-08-02：「这个规律系统，应该就是很简单的按照收集到的告活来整合就好啊，怎么会那么混乱？」「设备只做收集，后台负责统合与判断，是对账户的学习，不是对设备的学习。」「关于『我当时在观测』，这个要求基本上就是在展示对于『告活功能』的不信任。如果要加强这点，应该是直接对告活的质量本身进行提升，而不是多一个『监测』。」提案见 [[KC Routine Learning Simplification]]。

---

## ADR-0036 · 2026-08-02 · accepted

**决策**：
1. **紧急位置与紧急联系人独立解耦**：UI 与数据结构中，「紧急联系人 (Emergency Contacts)」与「紧急位置 (Emergency Locations)」划分为两个完全独立、互不遮蔽的区域。
2. **多卡片手写位置与简洁 GPS 预授权 (Frontend User Settings)**：
   - **多卡片手写物理位置 (Multiple Manual Address Cards)**：允许用户配置多个具体的物理位置卡片（如：家 `"Home: Unit 402, Gate Code #1234"`、办公室 `"Office: Fl 18, Desk B4"`），弥补室内/高楼 GPS 模糊的盲区。
   - **简洁 GPS 预授权开关 (Simple Pre-authorization)**：客户端设置页仅提供清晰简洁的描述：“*危机动态 GPS 授权：开启后，当触发 SOS 时系统将自动发送当前设备的 GPS 坐标*”。前端设置项**不向普通用户标注 `last device` 等技术术语**，保持平视简洁。
3. **后台与救援者/守护者侧的多设备存活 GPS 标注 (Backend Rescuer Telemetry Resolution)**：
   - 当收到 SOS 告警时，后台会将该账户下所有登录设备上报的位置信息整合推发给救援者/守护者，并在地图与 Timeline 中**清晰标注哪一台是“最后确认有告活记录”的设备**（例：`📍 GPS Dispatch: 37.7749, -122.4194 (来自 Android Phone · 5m前最后存活设备)`），帮助救援人员精准锁定救护目标。
4. **告活记录中的 GPS 可选性与平台优雅降级 (Optional GPS on Liveness Pings)**：
   - App 本身受限于平台与隐私，绝非实时轨迹追踪工具，Timeline 展示的是“告活记录 (Liveness Check-in Events)”（仅包含发送设备与告活时间戳）。
   - **用户自主开关**：由受守护用户自主决定是否在每次告活时附带 GPS（`☑ 在每次告活时附带当前 GPS 位置快照`）。
   - **平台优雅降级**：若用户未开启授权、或操作系统平台（如 iOS PWA 后台限制）权限复杂繁琐，系统**绝不拦截或强制索取**，直接平滑降级为只上传“设备名称 + 告活时间”的纯净存活记录。

**理由**：手写多卡片门牌号是急救人员进门救人的物理钥匙；前端设置项必须保持平静极简；`last active device` 属于后台提供给救援者的信息；而告活记录随附 GPS 必须服从用户自主选择与平台优雅降级，不能造成权限骚扰。

**影响**：
- UI 端：Profile / Routine 中增加 `☑ 告活时附带当前 GPS 坐标快照` 可选开关。
- Timeline 端：完美兼容有 GPS 坐标的告活记录与仅有设备+时间戳的无 GPS 告活记录。

**追溯**：人类在 2026-08-02 补充指导：“Timeline 那边受限于平台和隐私，只能说有告活记录（发送设备和时间）；GPS 的展示由受守护用户方选择是否要在每次告活时提供；如果平台本身有限制、不好拿权限、设置复杂的话，就不要在告活时提供 GPS”。

---

## ADR-0037 · 2026-08-04 · accepted（修正 ADR-0035）

**决策**：silence 阈值改为**这个账户自己观测到的正常沉默上界**，并从判定链上移除全部预设边界。修正 ADR-0035 的统计量选择，保留其三条宪法原则。

**统计量由 p95 改为顶端次序统计量**。p95 不是「上界」，它的定义就是「5% 的日常沉默会越线」——用它当告警线，密集账户每月必然响几十次。改为：把账户扣除睡眠窗后的间隔按长度降序排列，取第 `i` 个，`i = 1 + round(B × D / 30)`，其中 `B` 是每 30 天容许的误报次数（策略参数），`D` 是窗口内有证据的天数。证据越少 `i` 越小、线越靠外——还没见过这个人的长日子时，不假装知道他的上界。跳过最大值天然免疫单次掉线（知拉最长 13839 分钟是掉线，第二长 1385 分钟才是真实上界）。

**移除全部预设边界**：无 600 分钟天花板、无 `greatest(fixed_minutes, …)` 地板、无模板锚点、无「无数据者锚到常数 90」。人类 2026-08-04：「不去预设用户的日常频率的上下限，该什么就是什么，就那么简单。」**没有证据的账户不发明阈值**——不产生 silence 判定并如实标注，而不是用编造的数字冒充保护。

**ADR-0035 的收缩机制不再需要**：`n/(n+k)` 向 preset 群体中位数收缩本身就是一种预设，且方向错误（会把稀疏账户的线往下拉）。稳健性改由「`i` 随证据量变小、线自动外移」承担。常数 `k` 与其标定任务一并作废。

**持续摄入，无资格门槛**：不要求覆盖凭据或观测证明；旧记录是起点，新记录持续校准；不存在跨过样本门槛的跳变，也不存在样本老化后画像失效、静默退回模板的悬崖。人类 2026-08-04：「无论告活信号的采集未来会如何调整都好，Routine 的学习和 react 都应该要持续保持和直接学习与反应。」

**本层不承担判定精度**。人类 2026-08-04：「这只不过是其中一个比起每天主动签到一下就算是人好好的信号还要更加可靠一点点的信号罢了。」精准要靠信号内的多维信息加上后续的 AI 分析层，不能靠继续调这一层来补。

**触发本修正的实测证据**（2026-08-04 生产库）：07-20 以来 180 次 silence 告警，若每个账户用自己的正常上界，只剩 **12 次**（减少 93%），其中 9 次集中在一个临界账户。Karma Cheki 被开警时的平均沉默是 365 分钟，而他自己的正常上界是 1114 分钟。另查出：`alert_observation_coverage_intervals` 只有两个 tester 账户有行，7 个真实用户为 0；6 个账户的 `latest_evidence_at` 停在 2026-07-19（v1→v2 切换日），画像每天掉 6–8 个样本、掉 1 个支撑日，预计 2026-08-09 至 08-12 逐个跌破有效性、静默退回模板。

**代价（人类知情接受）**：稀疏账户会得到很长的线（知拉约 23 小时），接近没有保护——这是诚实的结果，无法把「手机关了一天」与「倒下了」区分开，与其用短线制造 16 次误报，不如承认这一层对他很弱。正常账户最坏发现时间拉长（Bernardo 约 7 小时、sanagu 约 11 小时），方向与 ADR-0035 一致。

**追溯**：人类 2026-08-04 给出四句判断（见提案 §0），并以「处理」授权本修正与其实施。提案见 [[KC Normal Upper Bound Threshold]]，实施见 `KC-ADR37-NORMAL-UPPER-BOUND-001`。

**悬置项已裁决（人类 2026-08-07）**：2026-08-04 暂缓的唯一一项是「无证据账户的阈值为 null，Routine 状态与小组活动界面把它渲染成 0」。人类裁决：**「这个是小事，暂时直接让它是 0 就好」**——接受 0 作为该情形的显示值，不另做 UI 处理。这与本 ADR 的「没有证据的账户不发明阈值」不冲突：判定链仍然不产生 silence 判定，被接受的只是展示层的呈现方式。`KC-ADR37-NORMAL-UPPER-BOUND-001` 据此解除阻塞并结案。
> 遗留观察（不阻塞）：0 在界面上读起来像「阈值为零 = 极度敏感」，与真实含义「无从判断」相反。若日后有账户因此被误读，改为显式的「证据不足」文案是候选，但人类已明确当前不做。

---

## ADR-0038 · 2026-08-08 · accepted

**决策**：**以生产库当前结构为基线，重新划一条起跑线。** 把生产库结构导出为单个基线迁移文件，现有 99 个迁移文件整体移到 `supabase/migrations-archive/` 存档，线上迁移账本备份后清空、只保留基线一行。此后一切数据库改动走 `supabase db push`，**Supabase 网页后台与 MCP `apply_migration` 不再是可接受的发布途径**——它们正是造成这次漂移的原因。

**触发**：`supabase db push` 在两个方向上都不可用，因此每一次未来的数据库改动都没有发布路径。`--dry-run` 报 `LegacyDbPushMissingLocalError`，并建议把 78 个远端版本标记为 `reverted` 后重推 75 个本地文件。

**CLI 的建议是危险的，其前提已被证伪**。它只比对版本号，而版本号恰恰是唯一失真的字段。2026-08-08 同时按版本号与名称做四路连接（102 条账本行 × 99 个本地文件）：

| 分组 | 条数 | 含义 |
|---|---|---|
| A | 24 | 版本号一致，本来就对 |
| B | 59 | **同一件事已生效**，线上用了另一个时间戳 |
| C | 16 | 两个键都对不上的本地文件 |
| D | 18 | 两个键都对不上的**线上账本行** |

C 组 16 个逐条探测生产库，**全部在线**（`set_monitoring_direction`、`private.is_group_admin`/`is_community_admin`、`app_versions.public_rollout`、`communities_delete`/`groups_delete`、两个索引、`supabase_realtime` 的两张表，以及 `20260807223000` 手工执行、账本无记录的 cron 修正——生产 `process_escalations` 里已含 `sleep_grace`）。**未执行的本地迁移数量为零**，按 CLI 建议推送等于重跑已生效的工作。

主要风险不是裸 `CREATE TABLE` 中途失败，而是那约 40 条 `CREATE OR REPLACE FUNCTION` **不会失败、只会覆盖**——把生产函数体静默换回旧定义，告警引擎退回旧逻辑且不报错。

**决定方向的是 D 组**：18 条迁移在仓库里没有任何文件，因此**无论怎么修账本，`supabase/migrations/` 都重建不出生产库**。它不是跑偏的第二份真相，是缺了一块的流水账。加上本地重放产出的函数体与 GRANT 早已与生产不同（[[KC Migration Replay Compatibility Baseline]]），这个目录从来就不是可信副本。「哪边是权威」因此不成立——生产库是唯一完整的记录。

**否决的两个方案**：(1) 改账本迁就本地文件——须给 D 组 18 条「补写」并非当初执行过的 SQL，把假记录固化，且目录仍重建不出生产库；(2) 改本地文件迁就账本——约 93 次文件操作，多数事后凭空重建，终点相同、活更多、同样是假记录。两者都栽在同一处：都假设本地目录可以成为完整真相。

**风险量级**：**本操作不对生产库执行任何 DDL**。被修改的只有 `supabase_migrations.schema_migrations` 记账表与仓库文件；表结构、函数、策略、数据全不参与。回滚 = 从账本备份恢复 + `git revert`，不存在数据丢失或服务中断路径。

**完整性要求（`db dump` 抓不到的）**：pg_cron 的 9 个作业是**数据不是结构**，schema dump 一个都不含。漏掉的后果是最坏的一种——重建出的库结构完全正确却**没有心跳**，告警引擎静默死亡且不报错。基线必须显式重新声明 `process-escalations`、`process-checkin-tasks`、`push-dispatch`、`passive-poll`、`prune-stale-clients`、`run-daily-aggregations`、`adaptive-alert-shadow-cycle-v1`、`adaptive-alert-shadow-maintenance-v1`、`account-shadow-cycle-v1`。已核查两个 `http_post` 作业只含 Edge Function URL 与空 body，不含任何凭据，可安全提交。此项由 `db diff --linked` 返回空作为唯一硬检测。

**代价（人类知情接受）**：**基线之前的历史不再能通过发布路径重放。** 99 个旧文件在 git 中可读可考古，但不再是可执行的重建路径。鉴于 D 组已确立「这条路径本来就不存在」，这是把一个已失效的能力正式注销，而非放弃一个还在用的能力。

**追溯**：人类 2026-08-08 在方向问题上选择「重新划一条起跑线」与「完整走：任务卡 + ADR」，审阅完整范围后以「做」授权执行。提案见 [[KC Migration Baseline Squash]]，实施见 `KC-MIGRATION-BASELINE-SQUASH-IMPL-001`。

**调查中撞见的独立缺陷（不由本 ADR 处理，见 `KC-NIGHTLY-REBUILD-ISOLATION-001`）**：`private.rebuild_account_normal_bounds` 自 2026-08-05 起每晚失败，全部账户阈值冻结在 08-04；根因是并行期遗留的对照字段 `live_threshold_minutes` 为 `NOT NULL`，与 ADR-0037「无证据不发明阈值」直接矛盾，且整个重算是单条语句、无按人隔离。同类脆弱性存在于 `process_escalations`、`process_checkin_tasks`、`run_daily_aggregations`、`apply_liveness_side_effects`——**做了失败隔离的反而是实验性的影子路径**。

---

## ADR-0039 · 2026-08-09 · accepted

**决策**：KC 进入 Store-first 稳定化收敛。现网继续运作；所有修复先在隔离集成线按独立包完成测试、Manager 复核、全量回归与回滚准备，任何 DB、Edge、Web 或二进制生产动作仍需单独取得人类授权。长期正式目标为 **Tauri 桌面、Google Play AAB、iOS Native**；APK 与 iOS PWA 是过渡渠道，不再拥有长期架构决定权。此项修正 ADR-0030 的 iOS-PWA-only 发版方向。

**Store-first 完成定义**：功能能跑不等于完成。每项能力还必须保证安全证据真实、权限/entitlement 被拒时诚实降级、与已发布客户端向后兼容、正式平台可签名构建、Store 申报/隐私/同意文案与实际行为一致。DeviceActivity/Family Controls 是需 Apple 批准的 managed capability；APNs 静默推送不保证送达，不能单独证明活动或健康覆盖；外部 TestFlight 不是免审核渠道。Android AAB 不得把 `specialUse` 或 full-screen intent 当作无条件核心前提。

**Concern**：只有目标已有 active alert 时，同组授权成员才可发送；Concern 不创建告警、不构成活动证据、不解除告警，只加强本人明确回应需要。资格由服务端执行，不能只隐藏按钮。

**正常静默学习（修正 ADR-0037 的证据准入）**：阈值仍是账户本人观测到的正常静默上界，不增加统一 floor、cap、preset 或 cohort template；但只有同一受信任原生 collector 在整段期间持续正常、服务端收到可验证连续覆盖、无设备/App/权限/网络/采集缺口的静默才有训练资格。outage、unknown、普通 PWA/浏览器、补传历史、告警/已知异常、Guardian/Shortcut/manual 均不得训练。异常长静默至少要在不同日期出现两个独立、相近、coverage-valid 的正常样本才可改变上界；单次极值不改写正常。无健康覆盖时结果为 Unknown/证据不足，不训练、不延长睡眠、不刷新活动，也不证明危险。

**守护健康**：健康时静默到底；守护失效时必须诚实显现。服务端按平台覆盖判断 outage，同一 incident 先向本人显示一次明确提示并持续标 `Limited`；关闭提示不恢复 Ready，只有新的连续健康覆盖才能恢复。失效区间停止学习，技术 outage 永不自动变成人身告警。普通组员只在名单查看状态；可私下将成员标为 **特别关注**，在本人提醒及额外健康宽限后订阅一次「设备/App 覆盖中断，不代表遇险」通知。特别关注默认关闭，只是通知偏好，不增加任何数据或操作权限。

**Guardian/Ward**：Guardian → Ward 是 KC 最高、最全面的照护授权层，不是特别关注或普通组员的增强版。关系须明确建立、可见、可撤销；active Guardian 可持续查看 Ward 的守护/设备覆盖、最近活动、Routine 证据、当前与历史告警、完整紧急资料，接收全部安全/守护通知，管理 Ward check-in tasks，并执行 Concern、联系协调与外部确认。即使 Guardian 也不可冒充本人活动、完成本人 Pattern 解锁、改身份/凭据/密钥、删除 Ward 账户、授予设备权限/GPS/生物识别/OS consent，或把外部确认写成个人学习证据。Guardian 外部确认可参与既有有界协调状态机，但不重置 effective silence、不训练 Routine、不永久替代 self confirmation。

**紧急资料**：联系人、手写地址、实时 GPS 是三类数据。联系人和地址使用正式多行模型，不再 JSON 塞入旧 scalar；联系人可有一个 Primary，地址无 Primary。Guardian 在 active 关系期间持续可见完整照护资料；普通组员只在目标告警到 Group 阶段临时获得完整紧急资料；Community 只获得救援必需最小字段；告警结束即撤销 alert-scoped 访问。授权和读取审计由服务端执行。GPS 按设备、按目的独立同意，静态地址不得冒充当前位置。

**不可变真相**：本人被动活动、本人明确解锁、Guardian 外部确认、Concern、技术覆盖恢复和通知 acknowledgement 是不同事件。sleep/post-wake grace 自动解除必须说出真实原因，不能再写成「检测到活动恢复」。

**实施边界**：本 ADR 只接受设计、Brain 真相、规格和后续实施计划；不授权 source implementation、migration、production、deploy、release、账号/权限变更或 Store 提交。完整规格见仓库 `docs/superpowers/specs/2026-08-09-kc-store-first-stabilization-design.md`；执行必须另建精确 write set 与 release gate。

**追溯**：人类在 2026-08-09 当前状态审计后逐项确认隔离集成＋分包上线、向后兼容、Store-first、Concern=A、重复且健康覆盖的静默学习、紧急资料分阶段披露、守护失效显式提示、普通组员特别关注，以及 Guardian/Ward 作为最高级全面守护但保留本人不可代理边界。`KC-STABILIZATION-DESIGN-001`。

### ADR-0039 修订一 · 2026-08-14 · accepted（「技术 outage 永不自动变成人身告警」的适用范围）

**触发**：人类 2026-08-14 降低被动签到的产品目标——KC 不再承诺及时发现意外，只需让用户按自设 `D`/`N` 进入既有漏斗，并比「每天手动签到一次」的市面产品方便一点点。该目标显式接受误判 `missed` 的代价。规格 `docs/superpowers/specs/2026-08-13-kc-passive-checkin-system-design.md` rev 5–8 据此把 `unknown` 移出计数路径，与本 ADR 原文的一句话产生冲突，故须限定而非推翻。

**原文不删一字。** 本修订只限定「技术 outage 永不自动变成人身告警」的适用范围。

**限定后的表述**：技术 outage 永不自动变成**人身**告警。但在 `engine_mode='passive_checkin'` 下，采集器沉默与**本人未回应**叠加时，可以进入既有漏斗——因为此时的证据已不是「采集器没上报」，而是「这个人对一次直接询问没有回应」，后者是关于人的事实。

**措辞是硬约束，不是建议**：任何到达 group 或 community 的文案必须表述为「KC 失去联系」，**不得**表述为此人遇险。这与本 ADR 守护健康段已定的「设备/App 覆盖中断，不代表遇险」是同一措辞标准，向下贯穿两级，不得在升级过程中被改写成危险表述。

**为什么这不是推翻**：本 ADR 原意禁止的是**用技术故障冒充人身危险**，不是禁止「通知」这个动作本身——证据是它自己就规定了「设备/App 覆盖中断」通知，并把它设为默认关闭的通知偏好。原文写「永不」时的前提是 KC 承诺可靠发现意外，那个承诺已由人类撤回；而手动打卡基准从不区分「你没打卡」和「你手机坏了」，此处也不存在一个要被污染的人身告警——漏斗第一级只打扰本人。

**继续有效、不受本修订影响**：失效区间停止学习（跨越采集器不上报区间的 episode 一律排除训练，这正是 ADR-0037 缺陷本身）；被动证据永不解除 open 告警；Concern/Guardian 外部确认/通知 acknowledgement 不构成本人活动；守护失效须诚实显现且关闭提示不恢复 Ready；特别关注默认关闭且不增加任何数据或操作权限。

**实施边界**：本修订只授权设计与规格层面的对齐，不授权 source implementation、migration、production、deploy、release 或 Store 提交。被动签到引擎本身的接受仍走 ADR-0042。

**追溯**：人类 2026-08-14 在读过本 ADR 全文后判定其对新目标「是帮助，不是多余」，并指示按追加限定、不删原文的方式落地。Claude 与 Codex 在 [[KC Passive Check-In Spec Revision 5 Review]] 四轮评审中均主张方案 A（采集器死等同漏签手动打卡），Codex 并补充要求「KC 失去联系」措辞须贯穿 group/community 两级，已纳入上文。

## ADR-0040 · 2026-08-10 · accepted

**决策**：确立 **信号收集** 与 **告警判断** 为两个独立层，并将告警阈值从「每账户一个数字」改为「分上下文的一组阈值」。触发于 Chunwei 2026-08-10 的两点质疑：单一全局阈值不成立；两层被混着讲、混着改。完整论证与实测见 `Coordination/Proposals/KC Evidence Layering and Contextual Thresholds.md`。

**D1 · 两层与接口契约**：第一层（信号收集与归一化）按平台各自实现，但产出必须归一为两类——带 `evidence_class` 的活动事件，与 `alert_observation_coverage_intervals` 覆盖区间（三状态轴，已是正确样板）。`evidence_class` 在入库时由懂平台的那层判定，取值 `self_observed` / `self_declared` / `external_confirmation` / `replayed`；只有 `self_observed` 可训练，且依 ADR-0039 一律不解除告警。第二层（告警判断）**不得引用任何平台或收集端词汇**，准入条件应退化为 `evidence_class='self_observed'` 加覆盖包含。新增平台只动第一层，改判断逻辑只动第二层。

**D2 · 分上下文阈值**：阈值改为按上下文分桶——小时桶、工作日/周末，并为周与周、月与月的差异预留扩展。**样本不足时回退到更粗的桶，不得回退到全局平均**，且回退层级必须可查以解释每次告警与不告警。冷启动可用 routine-mode cohort prior，但必须标注为 cohort 来源，不得冒充个人证据。

**D3 · 顺序不可跳步**：可信覆盖证据 → 分层纯重构 → 分桶阈值 → AI/cohort 综合判断。**分桶不修复污染，只会更精细地建模污染**：切成 48 桶后每桶样本更稀薄而污染比例不变，结果只是「这个钟点浏览器通常关多久」。

**弱覆盖准入（人类 2026-08-10 决定）**：iOS PWA 与桌面端可产出**较弱但如实分级**的覆盖凭据，并**允许参与训练**；前提是其等级被诚实标注、不得冒充原生采集器等级，且健康状态如实反映其强度。

**实测依据**：Chunwei 30 天 2396 个 gap，中位数 6.0 分钟、p90 24.5 分钟、p99 3.0 小时、月均 24 次超过 3 小时，算出上界 4.7h / 阈值 5.5h——一个每 6 分钟上报的设备不会自己安静 6 小时，该尾部由采集器在线时长决定而非用户行为。知拉为同一机制在断续设备上的放大：98.1h / 99.6h。生产 shadow model 实测 `day_partition=all_days`、`context_keys=personal_global`、cohort priors 0、shadow decisions 0，**证明「智能线」当前亦为单桶**。

**不采纳**：只换统计公式（输入不变，仍是采集器在线时长）；先分桶再谈覆盖（更稀薄且固化错误）；维持单一全局阈值（已产出无意义数字）；判断层继续认 `kind`/`source`（每加平台都要回改判断层，两层缺陷互相伪装）。

**与既有决策**：ADR-0039 全部保留，本 ADR 是其实现路径的分层化；ADR-0037 的 `account_normal_bounds` 权威保留，但「单一数值」形态由 D2 取代；ADR-0023 的 comparable-context / cohort prior 由影子设计推进为分层后的实施目标；ADR-0022 固定模板不恢复。

**实施边界**：本 ADR 接受方向与顺序，不授权具体实施、production、deploy、release 或商店动作；每步需另建精确 write set 与验收。

### ADR-0040 修订一 · 2026-08-10 · accepted（D1 具体化：覆盖的四态模型）

**触发**：C2 部署造成误报后复盘。人类指出两件事——(a) 覆盖的关键问题是「拿什么信号判断 App 没在运作」；(b) 正式目标一直是 **Tauri / AAB / iOS Native**，`iOS-PWA` 与 `APK` 只是过渡渠道，不得决定架构。

**已证伪的做法**：原 C2 把「覆盖」从**活动信号**推导而来。活动信号只在用户动手机时出现，因此系统只在人活跃时才敢称自己「在看」，学到的安静全是短的——这是 2026-08-10 误报的根因。**该缺陷与平台无关**：同样的推导方式在 Tauri 与 AAB 上一样错。

**修订后的定义**：**覆盖 = 守望者自己的心跳，与用户活动完全独立。** App 必须能在用户毫无动作时依然报告「我醒着、我在看、这段时间我没观察到活动」。这一段才是合格的安静样本。

**四态模型（人类 2026-08-10 提出并接受）**：

| 状态 | 含义 | 学习 | 告警侧处理 |
|---|---|---|---|
| `app_foreground` | 设备正常、App 正常运作 | ✅ 应学 | 正常判断 |
| `app_background` | 设备正常、App 后台静默运作 | ✅ 应学 | 正常判断 |
| `app_killed` | 设备正常、App 已被杀 | ❌ | **服务器主动尝试唤醒 App 并提示本人**，而非直接进入告警漏斗 |
| `device_off` | 设备未在运作 | ❌ | 记录为已知技术状态，**不得判为人身失联** |

`app_background` 正是原设计遗漏的一半，补上它即消除向下采样偏差。

**状态 3 与 4 的区分依据**：静默推送回执。传输层可达 → 设备活着 → `app_killed`；根本无法投递 → `device_off`。`public.notifications.delivery_outcome`（`sent` / `no_target` / `failed` / `native_missed`）机制已存在，此前未被用于判定 App 存活。

**设计对象明确为 Tauri / AAB / iOS Native**：Tauri 原生进程可发心跳；AAB 与 APK 共用同一条被动采集器，其能力已在生产实测（127 条 lease）；iOS Native 受后台限制只能部分做到，静默推送 best-effort 之限制依 ADR-0039 保持诚实表述。**`iOS-PWA` / `APK` / `desktop-web` 报不出状态 2 时如实标 `unknown`，此限制不构成架构约束，不得据以否定设计。**

**事实校正（2026-08-10 二次更正，前一版本记错了）**：我先前写「Tauri/desktop 原生 0 个」是**错的**。
真相是 **Tauri 客户端在生产中不可分辨**：`clientChannel()` 从不检查 `isTauri()`，桌面原生壳因此自称 `desktop-web`，
与一个浏览器标签页完全同名。Windows 桌面 App 实际一直在跑——本机 0.5.25 自 2026-08-03 常驻至今，
14 天内发出 1207 条 `source='tauri'` 活动 ping。**是遥测看不见它，不是它不存在。**

由此产生一个更重的结论：桌面守望者的**覆盖凭据一条都没落地过**。
服务端 `private.record_alert_shadow_coverage_lease_core` 要求 `clients.platform = 'tauri'` 才收桌面凭据，
渠道名对不上就返回 `capability_mismatch`——**而它是返回值，不是异常**，客户端 `catch` 永远看不到。
于是这台桌面每 5 分钟被静默拒绝一次、连续 7 天，服务器对它的观察记录始终为空。

这恰好是本 ADR 要修的那件事的实例：**活动那条腿通着，守望那条腿断着**，而且断得毫无声响。

**C2 重新部署的前置（在原三条基础上收紧）**：① 覆盖改由守望者心跳产生并带四态标注；② 判断层读取覆盖状态，`device_off` 期间不判失联、`app_killed` 期间先唤醒与提示；③ 最低覆盖比例门槛；④ 补「稀疏覆盖」与「后台静默期」两类行为测试。
人类同时授权 S3-C2（覆盖有效学习）先行部署生产，理由是其当时被评估为行为正确且受既有「最近一条可用记录」回退保护。**该评估随后被证伪**：2026-08-10 部署后立即出现覆盖稀疏导致的向下采样偏差，`Apk tester` 阈值由 20:02 收紧至 01:44 并触发一次误报（stage=self 关闭，0 通知）。已按人类指示撤回 C2。重新部署前必须先满足 D1 的判断层覆盖感知，并补最低覆盖比例门槛与稀疏覆盖行为测试。

---

## ADR-0042 · 2026-08-14 · accepted

**决策**：把 Keep Contact 的核心监测合同改为**账户级被动签到**。KC 不承诺即时判断人是否遇险；它以「比每天手动签到方便一点点」为基准，用正确绑定的个人设备在日常使用或携带中产生的合格证据替掉大部分手动签到。用户而非学习器拥有最终敏感度：自行选择收集间隔 `D`（20–360 分钟）、连续漏签数 `N`（1–1,000,000）及必选睡眠策略，界面持续显示名义等待时间 `H = D × N`。设置只有在服务端确认后才生效；每次生效建立新的、可追溯的 monitoring epoch，旧 epoch 不得跨界累计。

**确定性窗口合同**：每个 epoch 按半开区间 `[window_start, window_end)` 划窗，并使用平台到达宽限处理晚到但时间戳可信的证据。任何来自该账户**正确绑定表面**的合格事件都使该窗口 `checked_in`；宽限后仍无合格证据则为 `missed`。同一事件必须幂等，客户端时间只在有界时钟偏差内采信，重放、外部确认、Guardian/Concern、通知 acknowledgement 与单纯 collector heartbeat 均不得冒充本人活动。多设备只做账户级 OR 聚合：一台设备的合格证据足以签到，但任何单设备不得伪造另一设备的身份或能力。

**采集健康与告警权完全分离**：collector health 继续如实显示 `Ready` / `Limited` / outage 等状态，并用于排除学习样本、解释预计打扰率和提示权限修复；它**不得**把窗口改成 `unknown`、暂停 miss chain、延长用户的 `H`、阻止 self alert，或以技术健康度自动解除告警。技术 outage 本身不是人身危险；当 `N` 个完整窗口连续漏签后，系统只进入既有 self → group → community 漏斗，先向本人直接询问，且 group/community 文案必须说「KC 失去联系」，不得声称此人遇险。被动证据永不解除 open alert；解除继续只走 ADR-0039 的显式本人/既有有界流程。

**学习降权为建议**：学习器可以持续计算 `D_suggested`、`N_suggested`、预计每日打扰率与解释，但只能写 recommendation，永远不得修改 active settings、window outcome、miss chain 或 alert state。跨越 collector outage、权限缺口、重放历史或告警期的 episode 不得训练。平台工程 floor 只用于诚实展示与建议，不是服务端拒绝用户设置的下限；iOS Native 的 `H_floor = 12h` 目前是小样本的暂定工程值，必须由 iOS 真机 p95 证据到达间隔替换，不能据此宣称生产就绪。

**兼容与迁移**：账户模式为 `legacy` / `shadow` / `passive_checkin`。现有账户保持 `legacy`，不得静默迁移；新合同先在 `shadow` 中双算而不影响现网，只有用户明确确认 D/N/睡眠策略且服务端 ack 后才进入 `passive_checkin`。回滚只切回模式，不删除原始证据、epoch、window 或 recommendation。ADR-0037 的 learned silence 不再对 `passive_checkin` 账户拥有实时告警权；ADR-0040 D2 的自动上下文阈值对这些账户改为 advisory recommendation。两项 ADR 的证据分层、覆盖诚实性和训练污染防线继续有效；`legacy` 账户语义不被追溯改写。

**上线硬门槛**：至少 14 天 shadow；每个平台组合至少 20 个合格账户；推荐设置下的本人打扰率中位数 `≤ 0.2/日`、p90 `≤ 1/日`；Android 至少 3 台真实设备覆盖 OEM/Doze/权限拒绝，iOS 至少 3 组真实设备/系统组合覆盖 HealthKit、BGTask、静默推送、系统终止与用户强退事实，Tauri 覆盖 Windows/macOS 常驻、休眠与重启；安全、隐私、RLS/GRANT、幂等、时钟、睡眠门、兼容、回滚及 signed build 均通过。iOS force-quit 恢复能力在真机门前保持 unknown，不得在文案中夸大。

**实施授权与发布边界**：人类在 2026-08-14 书面授权本地实施计划、源代码、append-only migrations、测试、签名 release-candidate 构建和上线准备。该授权**不包含**生产 migration、数据库/Edge/Web 部署、公开 rollout、GitHub Release、Store/TestFlight/Play 提交、账号/权限变更或正式发布；这些动作仍各自需要当次人类 checkpoint。

**追溯**：规范 `docs/superpowers/specs/2026-08-13-kc-passive-checkin-system-design.md` revision 10 是本 ADR 的规范性细节来源。Claude 与 Codex 对 revision 5–8 的四轮独立评审关闭七项发现并共同判定方案可实施；revision 9 记录人类对 ADR-0039 冲突与 iOS floor 的裁决；revision 10 只把 HealthKit 的系统终止语义校正为与 Apple 已核实行为一致，并将用户强退保留为真机待证。Brain 提案见 [[KC Passive Check-In System]]，设计任务 `KC-PASSIVE-CHECKIN-DESIGN-001` 已归档。



---

## 2026-08-15 人类指示（0.7.0 发布路径修订，scope=KC 0.7.0 release plan）

人类 2026-08-15 明确指示：**跳过 canary 积累阶段，0.7.0 客户端直接正式发布**。执行结果：GitHub Release `v0.7.0` 转正（非 prerelease、Latest）、`app_versions` 0.7.0 = `released`、生产 `version.json` 发布 0.7.0（指向 GitHub 不可变资产 URL，APK 5,388,153 bytes 已哈希验证）。

**不变的安全边界**：live activation（`20260814201500`）仍推迟；所有账户 `legacy`；被动签到引擎继续 shadow-only；正式权威切换仍需 14 天影子证据 + 激活 migration + 新一轮人类 checkpoint。本指示只改变客户端发布时机，不改变权威门。

**证据**：`KC-RELEASE-0.7.0-STAGE1-001`、`KC-RELEASE-0.7.0-CANARY-001` 两轮守护任务 completed（Opus 5 独立审计各轮 verdict）。发布提交 `ade2a8e`。

---

## 2026-08-16 人类指示（充电插拔 = 告活信号，scope=KC 被动采集产品语义）

人类 2026-08-16 明确指示：**充电插拔（POWER_CONNECTED/DISCONNECTED）属于"告活信号"的一种，所有平台都必须采集**。此前实现把充电采集当作可选传感器（phone_charger）且受 keyguard/前台限制，与产品语义不符。

**确认的事实（2026-08-16 生产实测）**：

- 生产 ping v18（2026-08-14 部署）已含 0.7.0 `last_active_at` 补报代码。实测 unlock 补报行 gap 5–16 分钟。无需重新部署。
- Android 0.7.0 充电采集两条路径均受限制：证据路径只在 app 前台（运行时接收器）；ping 路径有 keyguard 门（锁屏返回 false）。锁屏/后台插拔 = 零采集。实测 APK 用户 `power_transition` 证据 0 条。
- iOS 0.7.0 已有前台电池监听代码（PassiveGuard.swift：batteryStateDidChangeNotification + 5 秒稳定确认 + power_transition 证据），但 observer 注册位置有缺陷（在 recordDirectEvidence 内，重复注册，且首次注册依赖直接证据事件）。iOS OS 不提供后台电池事件：进程挂起期间的插拔不会通知，0.7.1 改为 arm() 注册 + 前台追赶（下次前台对比状态，按观察时间上报）。
- 解锁采集正常：即时 ping 依赖进程存活；补报路径 ≤15 分钟延迟，实测生效（kind=unlock 行 gap 5–16 分钟）。

**修复方向（待人类批准后实施）**：Android manifest 接收器直接入队 power 证据并移除 keyguard 门对 POWER_* 的限制；iOS 前台电池监听；服务端如需区分充电 ping 需扩 kind。均为客户端改动，需新 APK。

**执行结果（2026-08-16，人类批准"没有冲突就修复，需要发 0.7.1 就发"）**：修复提交 `312589c`，PR #3 合并 `1e7a21a`；GitHub Release `v0.7.1` 发布（非 prerelease、Latest）；`app_versions` 0.7.1 = released；生产 `version.json` = 0.7.1（GitHub 资产 URL）；TestFlight run `31909089198`（ios-v0.7.1）触发。Artifact SHA-256：APK `39a59329…`，AAB `69382aad…`，EXE `99694969…`，MSI `bf125998…`。权威不变：activation 仍推迟，全部账户 legacy。Tauri/PWA 充电采集未做（证据注册表不含 power_transition，桌面电源状态不属于告活语义；如需另开提案）。

---

## 2026-08-16 Claude 独立审计（0.7.1 更新 URL，人类指示）

审计执行：Claude CLI headless，主仓库 `7e6313f`，Brain 任务 `KC-071-URL-AUDIT-FIX-001`（owner Claude，reviewer Human）。

**发现**：

1. FAIL：GitHub Release v0.7.1 缺 `keep-contact-v0.7.1.aab` 资产。本地 `release-artifacts/` 有该文件，但从未上传。现有资产：APK、EXE、MSI。
2. PASS：APK/EXE 下载 URL 均 200（签名重定向后）。
3. PASS：Vercel `version.json` = 0.7.1，URL 带 v 前缀，全部 200。
4. 旧：Android 内嵌 version.json 0.6.1、iOS 内嵌 0.5.25。已改 0.7.1（gitignore 构建副本，仅磁盘）。
5. BUG：`promote-release.mjs` 生成无 v 资产名。已修（1 行）。同 bug 在 `scripts/release-canary.mjs:123`（未修，下个 canary 前必须修）。
6. 真相：Android/iOS 更新按钮读远程 Vercel `version.json`（`src/features/update/versionCheck.ts:75-79`）。内嵌副本不被读取。更新正确性无需重发 APK。
7. PASS：local-gate 绿（467 测试 + typecheck + vite build）。

**结论**：APK 更新按钮 URL 正确，问题闭环。残留待人类决定：aab 是否补传；canary 脚本命名修复（0.7.2 前）。

---

## 2026-08-16 0.7.1 APK 版本循环根因（用户实测报告）

**症状**：安装 0.7.1 APK 后 Me 页显示 0.7.0；更新按钮循环提示下载 0.7.1，装完仍 0.7.0。

**根因（已证实）**：发布的 0.7.1 APK 内 JS bundle 编译产物仍是 0.7.0（`grep "0\.7\.[0-9]\+"` 只有 0.7.0）。构建时 `dist/` 是旧的：version.ts 升 0.7.1 之后未重跑 vite build 就打包。原生 versionName/versionCode 和 assets/public/version.json 是 0.7.1，唯独编译进 bundle 的 APP_VERSION 是 0.7.0。Me 页和更新比较都读 bundle 常量 → 永远 outdated → 无限循环。

**审计缺口**：前次 Claude 审计只查源码文件和 URL，未检查发布 APK 内部的编译 bundle。审计清单新增：发布前必须解包 APK 验证 bundle 版本字符串。

**修复**：工作树重跑 vite build + cap sync + gradle（versionCode 88→89），三处全 0.7.1 验证通过。新 APK SHA-256 `1235cd608efbde80de0258947f02957ba98a3fec668ef2593cb1f0c268791c92`。提交 `37fd9f6`。GitHub 资产替换等人类授权。

**执行结果（2026-08-16 人类授权替换）**：GitHub release v0.7.1 APK 资产已替换为修复版（同名 `keep-contact-v0.7.1.apk`，size 5,387,971，bundle 解包验证只含 0.7.1）。Vercel 同步替换（提交 `53af43e` 推 main，staged 资产重建）。下载 URL 200。循环修复闭环。发布审计清单新增 bundle 解包验证（见上文）。

## ADR-0043 · 2026-08-17 · accepted
**决策**：KC 停止用被动侦测取代签到，改为用被动侦测**豁免**签到。「每天问你一次，除非你明显已经在用手机。」
1. **合同定义**：每日签到作为一个连续窗口。用户配置：每日询问本地分钟 `ask_at_local_minute (0..1439)`、豁免回溯时长 `waiver_lookback_minutes (240..2880)`、响应宽限时长 `response_grace_minutes (15..720)` 及时区 `timezone`。模式为 `legacy` / `shadow` / `passive_checkin`。
2. **免签机制**：若回溯窗口内存在合格被动证据，则该日签到自动标记 `checked_in`；若无证据且过宽限期，则触发 self 阶段询问，漏签按 `consecutive_misses=1` 处理。
3. **推翻与继承**：推翻 ADR-0042 的窗口网格结构（D×N、360 分钟上限、learned recommendation）。保留不变：证据合格规则、设备绑定/凭证吊销/幂等/时钟、隐私与留存、既有 self→group→community 漏斗、被动证据永不解除 open 告警、采集健康与告警权分离。
**理由**：窗口网格模型下，采集器失效会导致连续漏签累积，打扰反而增多。豁免模型下，采集器死掉最多每天问一次（与传统签到基准一致），绝不发生打扰爆炸。
**影响**：已应用迁移 `20260816100000_passive_surface_health_writer.sql` 与 `20260817000000_daily_checkin_with_activity_waiver.sql`；前端 Routine 重构为三个直观选择控件；全平台发布 v0.7.2。
**追溯**：人类 2026-08-17 明确决策；市场签到竞品实证调研。

---

## ADR-0044 · 2026-08-21 · accepted
**决策**：接受清醒滚动死线（Rolling Awake Deadlines）、沉默原因定名（Named Silence Cause）与精准敲门（Targeted Knock）架构，并在 0.7.4 正式实施：
1. **清醒滚动死线**：睡眠窗时间不计入清醒超时（`20260821020000_deadlines_roll_and_sleep_is_not_counted.sql`）；窗口死线锚定于窗口内最新合格证据动态后滚（`f413137`），`my_daily_checkin` 统一返回服务端计算的 `next_deadline_at`。
2. **沉默原因定名**：超时关闭时记录精确分类：`silent`（人无动静）、`device_unreachable`（设备不可达）、`collection_restricted`（采集受限/权限丢失），通知与健康系统按原因分流，绝不把技术 Outage 误报为人身危险。
3. **精准敲门**：仅在死线前 1 小时内向可能超时的对象发送敲门推送，不再全量唤醒；`passive-poll` 仅向到期对象签发 push token。
4. **自证摩擦与解耦**：支持 Pattern 与 Passcode 双解锁本地自证；被动活动永不解除 open alert。
**理由**：消除睡眠窗期间虚假扣减超时导致的晨间误报；让通知文案准确区分人身沉默与技术故障；降低推送与设备唤醒消耗。
**影响**：已应用迁移 `20260820230000`–`20260821040000`；Routine/Me 界面全面重构并同步契约；全平台发布 v0.7.4，518 项测试全部 PASS。
**追溯**：人类 2026-08-21 批准契约对齐计划与 0.7.4 发布。


## ADR-0045 · 2026-09-23 · accepted

[Codex · 2026-09-23 11:50 +06:00]

**人类指示（本任务原文）**：「把用户必须解锁 pattern 来解除告警的逻辑，换成仅指定守护者对被特殊守护者可额外设置的功能，一般情况，只要检测到用户本人的活动，都可以自动解除告警。状态确认通知用横拽 bar，不行就普通按键。」

**已接受规则**：默认由服务端合格的本人新活动解除自动告警；有效指定守护关系可另行开启 pattern 要求，默认关闭；普通状态确认使用一切安好按钮。此决定替代 ADR-0039/0042/0043/0044 中「所有被动活动永不解除 open 告警」及默认强制 pattern 的要求。

**实现范围**：活动仍须满足既有来源、账户、v2、时间与幂等验证；历史补传、心跳、守护者确认不得冒充本人活动。特殊守护要求只限有效关系，服务器校验；普通小组成员不能开启。主动 SOS 保留显式取消（作为本次实现边界，已告知人类）。保留历史事件与通知记录。

**交付状态**：授权实施与本地验证；尚未部署。上线、原生新安装包分发仍为单独发布步骤。

---

## 快记

> 一行一条：日常的决定，和人类接受的新知识。正式的、不可逆的决定仍写成上面的 ADR。规则见 [[Human Preferences]] P14。
> `- 日期 · 决定 · 一句话 · 原话「…」 · 理由 · 来源：人类|AI 推导 · 复查：日期|无`
> `- 日期 · 学到 · 一句话 · 来源 · 状态：未验证|已验证`
- 2026-11-02 · 决定 · 选 A：设备联系不上（miss_kind=device_unreachable）的沉默告警最多升到 group 或 community，不进 terminal，不解锁地址与紧急联系人；silent 告警不变 · 原话「A」 · 理由：设备拔电/没电不是人身失联（ADR-0040 修订一）；近 30 天 6 条此类告警升到 terminal · 来源：人类 · 复查：实现并上线后核对 terminal 通知数
- 2026-11-02 · 待人类裁决（未决）· collection_restricted（采集被关/无权限）是否同样封顶；人类只选了 device_unreachable，实现者不得自行扩大 · 来源：AI 推导
- 2026-10-30 · 决定 · 不升级 Supabase 付费规格，KC 生产库继续用 Free Nano；靠已做的清理和看门狗兜底，再卡死时重新评估 · 原话「不要花钱」 · 理由：人类不愿为此付费；清理后连续 5 小时 0 次任务失败；风险：磁盘读写额度仍只剩 17%，5 小时没有回升（控制台读数） · 来源：人类 · 复查：2026-11-30
- 2026-10-09 · 学到 · 生产近 30 天 31 条沉默告警全部分类为 device_unreachable，其中 6 条升到 terminal（解锁地址与紧急联系人）；与 ADR-0040 修订一“device_off 不得判为人身失联”存在落差，待人类裁决，详见 Known Issues KC-OUTAGE-ESCALATION-20261009 · 来源：生产只读查询 2026-10-09 · 状态：已验证（事实），是否违背意图未验证
- 2026-10-08 · 决定 · 暂停 B（另找证据来源）：其前提“拔电沉默是产品核心缺陷”与 ADR-0042/0043/0044 不符（目标已降为比手动签到方便一点点；沉默=最多每天问本人一次，原因标 device_unreachable，群通知须写“KC 失去联系”）；“可见的还好吗通知”就是已有的 self 阶段 · 原话「怎么感觉你好像不清楚Profile的最新决定？」「Keep contact在Obsidian里怎么可能会没有Profile呢？？？？」 · 理由：人类指出 AI 不清楚画像（Profile）相关的既有决定 · 来源：AI 推导（据人类纠正）· 复查：人类确认“Profile”所指后
- 2026-10-08 · 学到 · 实测：iOS 测试账号近 21 天 11 次 silence 告警，6 次升到 group 及以上，2 次到 terminal（开 21 h、13 h）；约 0.5 次/天，高于 ADR-0042 门槛（本人打扰率中位数 ≤0.2/日）。单账号测试机，样本 1 · 来源：生产只读查询 2026-10-08 · 状态：已验证（事实），含义未验证
- 2026-10-08 · 决定 · iOS 拔电时不响应：人类选 B（另找证据来源），不接受“只显示有限”作为终点 · 原话「B」 · 理由：实验证明敲门频率不是原因 · 来源：人类 · 复查：2026-10-15
- 2026-10-08 · 学到 · 原 B 的例子“客户端每小时上传步数点”只改善事后记账，不能在拔电静默期产生证据：窗口链只数末尾连续 missed，迟到的一个点已足以清除链，但静默期内的告警仍会先开出 · 来源：AI 推导（passive_window_engine / rolling deadlines 迁移，未做实机验证） · 状态：未验证
- 2026-10-02 · 决定 · 批准并放行 24 小时 iOS 敲门实验（仅测试账号，生产函数临时改动，到点自动失效） · 原话「批准，做那个 24 小时实验」「放行，现在执行」 · 理由：拔电时 iPhone 不响应的原因未证明，需要实测 · 来源：人类 · 复查：2026-10-03（读数并还原函数）
- 2026-10-02 · 决定 · 本地重放套用生产权限（只收回、不授予的快照），让 4 个 ACL 断言在本地可验证 · 原话「做，让本地重放套用生产权限」 · 理由：这 4 项在生产正确，本地永远红会掩盖新问题 · 来源：人类 · 复查：2026-12-01（生产 ACL 变更时刷新快照）

