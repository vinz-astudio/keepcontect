# 🧠 2nd Brain — 架设规则

> **任何 IDE、AI 助手在向此 vault 添加内容前，必须先读完本文件。**
> 本文件定义了这个 Brain 的结构逻辑、分区规则和操作规范。

---

## 一、三个区域的定义

### 📚 References（参考区）
**放什么**：通用的、可复用的、与特定项目无关的知识。
- 成熟的技术规范和最佳实践
- 可迁移到任何项目的设计模式
- 工具使用指南（如 Supabase、PWA、Git 等）
- 术语表、概念解释

**不放什么**：项目特有的业务逻辑、具体用户数据、某项目的历史记录

**路径**：`References/<主题>/<文件>.md`
示例：`References/Engineering/Supabase Patterns.md`

---

### 🗂 Projects（工作区）
**放什么**：每个项目的"正确的样子"——目标、架构、业务规则。
这里的内容应该是**当前状态的真相**，不是历史，不是过程，而是"这个项目现在应该是什么样的"。
- 项目首页（目标与核心原则）
- 核心不变量与指针地图（Invariants & Map）
- 系统架构概览
- 数据库/数据结构定义
- 核心业务逻辑与规则
- 模块职责说明

**不放什么**：改动历史、问答记录、实验性内容、已废弃的方案

**路径**：`Projects/<项目名>/<文件或子目录>.md`
示例：`Projects/Keep Contact/Business Logic/Alert System.md`

**每个项目必须有的文件**：
- `Projects/<项目名>/<项目名>.md` — 项目首页，包含目标和核心原则
- `Projects/<项目名>/<项目名> Invariants & Map.md` — 核心不变量与指针地图（<=800 tokens）。**任何 AI 在执行项目任务前必须自动首先读取本文件**，建立顶层漏斗与红线约束，严禁盲目通读所有文档。

---

### 🌊 Experiences（沉淀区）
**放什么**：随时间积累的经验、历史记录、来回问答、进度追踪。
- 开发日志（改动意图记录）
- 问题追踪（已解决 / 待解决）
- 决策历史（为什么当时做了那个选择）
- 跨项目的经验总结

**不放什么**：当前"正确状态"（那个在 Projects）、通用规范（那个在 References）

**Templater 模板路径**：`Templates/`（vault 根目录下，非隐藏文件夹）/<项目名或主题>/<文件>.md`
示例：`Experiences/Keep Contact/Dev Log.md`

---

## 二、添加内容的决策树

```
这个内容是…
    │
    ├── 通用的，可以用在任何项目？
    │       → References/
    │
    ├── 某个项目"现在应该是什么样子"？
    │       → Projects/<项目名>/
    │
    └── 某个项目的历史、过程、问答、积累？
            → Experiences/<项目名>/
```

**有疑问时**：问自己"如果这个项目重头开始，这个内容还有用吗？"
- 有用 → Projects 或 References
- 只是记录过去发生了什么 → Experiences

---

## 三、添加新项目的步骤

1. 在 `Projects/` 下建立 `<项目名>/` 目录
2. 创建 `Projects/<项目名>/<项目名>.md` 作为项目首页，包含：
   - 项目目的（一句话）
   - 核心价值
   - 给 IDE/AI 的核心原则（不可违背的规则）
   - 技术栈速查
   - 内部笔记链接
3. 创建 `Projects/<项目名>/<项目名> Invariants & Map.md` 作为核心不变量与指针地图（<=800 tokens）
4. 按需建立子目录（如 `Architecture/`、`Business Logic/`）
5. 在 `Experiences/<项目名>/` 下建立 `Dev Log.md` 和 `Known Issues.md`
6. 在 `Home.md` 的工作区入口中添加链接

---

## 四、文件与命名规范

### 文件名
- 使用**英文**，单词首字母大写，空格分隔（Obsidian 会自动处理）
- 清晰描述内容，不用缩写
- ✅ `Alert System.md` / `Database Schema.md`
- ❌ `alert.md` / `db_schema.md`

### 标签（Tags）
在文件顶部 frontmatter 或正文中用 `#tag` 标记：

| 标签 | 用途 |
|---|---|
| `#project` | 项目相关内容 |
| `#engineering` | 通用工程规范 |
| `#business-logic` | 业务逻辑规则 |
| `#architecture` | 系统架构 |
| `#dev-log` | 开发日志 |
| `#issues` | 问题追踪 |
| `#glossary` | 术语/名词 |
| `#active` | 项目/议题正在进行中 |
| `#archived` | 已归档，不再维护 |

### Wikilink 规则
- 跨文件引用一律用 `[[文件名]]`，不用完整路径
- 链接时用**文件名**不用目录路径（Obsidian 会自动解析）
- 每篇文章底部加"相关笔记"列出关联文件

---

## 五、内容更新规范

### Projects 区更新
- 当业务逻辑、架构、数据库结构发生变化时，**直接更新**对应文件（这里存的是"当前正确状态"）
- 同时在 `Experiences/<项目名>/Dev Log.md` 中**追加**一条记录，写明改动的意图和背景

### Experiences 区更新
- Dev Log：在文件**顶部**（最新在前）追加，不修改历史记录
- Known Issues：更新状态（🔴待处理 / 🟡待观察 / ✅已解决），解决的问题移到"已解决"区

### References 区更新
- 内容更新即修改，保持内容最新
- 如有重大版本差异，在文件内注明适用版本

---

## 六、不要做的事

- ❌ 不要把项目的历史记录放进 Projects（那是 Experiences 的职责）
- ❌ 不要把特定项目的业务逻辑放进 References（那是 Projects 的职责）
- ❌ 不要在 Projects 里创建"草稿"或"实验"文件（Brain 里的 Projects 内容应该是可信赖的）
- ❌ 不要用中文命名文件（Obsidian 可以处理，但路径中文在某些工具里会出问题）
- ❌ 不要修改本文件（`Brain Rules.md`）而不同时更新 `Home.md`

---

## 七、给 AI 助手的附加指令

当你被要求向此 Brain 添加内容时：

1. **先读本文件**，确认内容应该放在哪个区域
2. **先读项目首页**（`Projects/<项目名>/<项目名>.md`）与 `Invariants & Map.md`，了解项目的核心原则
3. **不要创造新的顶级目录**，除非三个区域都不适合，并得到用户确认
4. **更新 Projects 后，同时更新 Experiences 的 Dev Log**
5. 只有新增 / 删除导航入口时才更新 `Home.md`；普通内容变更不要制造索引噪音
6. 如不确定放哪里，**先问用户**，不要自行决定
7. **无源不立笔记 (No source, no note)**：任何 AI 在新建或更新笔记/代码时，必须基于 Vault 中的地面事实（Projects 首页、ADR、References 等），严禁凭空捏造不存在的文献、数据或未在 Vault 中备案的逻辑。
8. **认知张力保护 (Cognitive Friction)**：当新引入的知识、规则或修改与已有笔记/ADR 存在冲突时，严禁 AI 暴力覆盖。AI 必须使用 `[CONFLICT]` 标记锁定冲突节点，并新建提案/ADR草稿，将任务状态挂起为 `awaiting-human` 交付人类裁决。
9. **第一性原理修复 (First-Principles Repair)**：任何修复、事故处置、回归修正、数据/可靠性/UX/性能修复，必须先从有来源的根部需求推导，不得先选前端/后端补丁再反向解释。最小链路为 `来源 → 根部需求 → 可验证不变量 → 当前差距/症状 → 因果链/根因 → 根因所属层 → 根部不变量 + 真实用户路径验证`。前端修复只有在证据证明底层数据、领域规则、后端与契约已满足不变量、问题纯属展示/渲染/交互层时才是根修复。根因未证实时只可标记为可证伪假设并做有界诊断；紧急止血必须标 `containment-only`、绑定永久修复，不得冒充根因已解决。Tiny 可压缩成 1–3 行，但不能省掉从需求到验证的逻辑。

---

## 八、多 IDE 协作（Codex / Antigravity / Claude Code / 其他）

多个 IDE 同时开发时，用 `Coordination/` 做**异步、文件化、人仲裁**的桥梁，完整协议见 [[Coordination]]。最低要求：

1. **Direct work is the default.** 请求清晰、可逆、在范围内、无增量付费且未触发保留权力时，当前合格 Manager 直接调查、修改、验证并收口；不为证明“无需治理”而建卡。
2. 没有通用的时间或 token 审核线（人类 2026-10-02 删除）。**Approved task execution envelope** 绑定目标、provider/data scope、增量支出上限及明确的时间、token、重试或阶段门。额度内累计 gross/cache tokens 只属 diagnostic telemetry，不形成重复 token-only checkpoint。
3. **Guarded work** 才启动 schema-v1 / policy-v3 task、读取 generated Task Context、运行 `brain-task check`，并通过 `brain-task update|finish` 管理证据和看板。重大 / 不可逆改动仍必须先有人类 accepted ADR。
4. Brain memory 使用 **event-driven memory**：仅在项目真相、accepted decision、handoff、未解 blocker、release/production 状态发生持久变化时回写。代码 / migration / 测试 / live runtime 是运行时真相。
5. **内部机器 delta，最终 STE100**：agent↔agent、Manager↔Executor/Auditor、thread、scratch、status 与内部 evidence packet 使用 `caveman-delta-v1`；默认一行 `machine-delta-v1` JSON，JSON 无法安全表达时回退到 `STATE | FACTS | ACTION | BLOCKER/NEXT`。空项省略；路径、命令、hash、数字、错误和证据必须精确；无新增写 `{"v":1,"s":"no_delta"}`。不发寒暄、夸赞、复述、计划旁白、重复状态或重复上下文。不使用 literal binary/Base64。**面向人类沟通（全局强制）：用户是 ADHD，绝不啰嗦，先结论、直奔主题、拒绝废话**；使用 [[STE100 Communication Protocol]]；不得因省 token 丢失安全事实、冲突、不确定性、失败验证或必填 receipt 字段。权威规则见 [[ADR-0041 Caveman Internal Communication]]。


## 九、统一 SDLC 协议（所有 IDE 必读）

所有由本 Brain 管辖的项目默认按 [[Coordination/Agent Runtime]] 执行（ADR-0045），设计语义以 [框架规范](Coordination/Proposals/agent-framework/spec.md) 为准。[[SDLC Unified Workflow]] 是受控工作（guarded work）的流程协议（版本号以该页 frontmatter 为准）；角色与模型选择只看 Agent Runtime Owner 节，[[Model Routing Guideline]] 只作能力参考与额度交接规则。M4 三强只用于项目定义级策划；M1–M3 先按 capability/risk/outcome/health 选择合格 provider，再选其最低够用 model tier，当前 IDE 不自动成为 owner。低风险 Standard 以确定性验收完成，不做 ceremonial 独立 audit；Product/UX、High-risk、Release 与有证据的 handoff-sensitive 工作只在集成后做一次独立 audit。

最低要求：
- 普通可逆工作使用最小相关真相和比例化确定性验证，不加载完整 SDLC，不创建 Task Context，不要求独立模型复核。
- Guarded work 才由 `brain-task start` 校验分类、write set、ADR、owner/reviewer 与受保护快照；此时 Generated Task Context 是 deep-module interface，[[Active Work]] 禁止手改。
- 架构、DB、auth/security/privacy、跨模块、不可逆、发布政策变更，仍必须先有人类 accepted ADR。
- M0–M4 按 [[Model Routing Guideline]] 选最低够用阵容；委派、独立 audit、route JSON 只在对应风险或经济性触发时启用。M4 3/3 只产生候选，不能替人 accepted。
- 完成后仅在 durable memory event 发生时更新 Projects 真相、Dev Log、Known Issues；Guarded work 再由 `brain-task finish` 校验其受保护快照和 write-back。

IDE 原生 skill / plugin 只能做薄桥；不得复制一份会过期的协议。Canonical 文件是 single source of truth，adapter/skill 只保留 context pointer。若本文件、adapter、skill 文字冲突，以框架规范与 [[Coordination/Agent Runtime]] 为准；受控工作的流程细节以 [[SDLC Unified Workflow]] 为准。

## 十、AI 角色与经验沉淀

1. 角色与委派规则只以 [[Coordination/Agent Runtime]] Owner 节为正本，本文件不重述。
2. 经验不通过每任务学习流水线晋升。可复用事实只有在形成 durable project truth、accepted decision、handoff/blocker 或明确的人类方向时，才写入相应 canonical note；不从单次聊天猜偏好。
3. 方案默认免费、本地、开源且 **no incremental spend**。付费、metered、card-required、proprietary-only 或 cost/license 未知方案不得静默启用。

## 十一、订阅额度与自动切换

1. 当前配套、配额语义、短期使用快照与付费功能状态的脱敏正本是 `Coordination/Provider Access Registry.json`；运行 `node Coordination/tools/model-routing-check.mjs entitlements Coordination/Provider Access Registry.json` 校验。Context window 与 plan quota 必须分开，供应商未公布固定 token池时写 `null/not-published-dynamic`，不得从百分比或上下文窗口猜 token。
2. **Included subscription tokens are authorized capacity, not incremental spend.** ChatGPT Plus、Claude Pro、Google AI Pro 套餐内可用额度该用就用；token 继续作为 context、loop、routing 与可观测性证据，不作为单独的付费理由。Call/tool/repair/scope/safety 断路器仍有效。
3. 遇到 quota exhaustion、provider unavailable 或 model 不满足 floor，当前语义 Owner／Manager 在已获批 provider/data scope 内自动 reroute；不要求用户重复授权。只有扩大 scope、超过已记录支出上限或缺少必需审计席位才 checkpoint。
4. API billing、usage credits、overages、auto top-up、upgrade、新订阅或任何 incremental charge 都必须先有明确、限额、到期的 **human authorization**。Chargeability 不明时按不可用处理；绝不静默开启。
5. M4 或独立 auditor 必需 provider 缺席时只能标记 degraded/blocked，不能让另一家公司冒充缺席席位，也不能报告成 consensus/pass。

## 十二、直接执行与事件记忆（ADR-0029）

**Direct work is the default.** 没有通用的时间或 token 审核线。**Approved task execution envelope** 内按 Manager、Executor、Auditor、retry、tool 与 reopened-context 聚合的 gross/cache tokens 是 diagnostic telemetry，不形成重复 token-only checkpoint。Brain 使用 **event-driven memory**，只记录项目真相、accepted decision、handoff、未解 blocker 与 release/production 状态的持久变化。权威规则见 [[ADR-0029 Direct Work Default and Event-Driven Memory]]。

保留人类权力包括 incremental spend、不可逆删除或数据损失、production/external action、account/permission/privacy 改变、product direction 或 accepted decision 改变，以及会实质改变结果的 ambiguity。普通工程职责不变：相关真相、范围控制、确定性验证、失败如实披露；Guarded work 只启用与实际 trigger 有关的 task/ADR/write-set/delegation/audit/release 控制。

## 十三、规则从「记录」改为「执行」（ADR-0046）

人类纠正或给出长期指示时，先分类，再处理。权威规则见 [[ADR-0046 Rules to Mechanisms (all projects)]]。

| 类 | 判定 | 处理 |
| :--- | :--- | :--- |
| A 能机器检查 | 违反时能用程序发现 | 写进该项目的检查器，挡住交付；文字规则从自动加载页删除 |
| B 流程步骤 | 要求某一步必须做过 | 写进交付回执或项目 Gate；缺回执就拒绝交付 |
| C 只能靠判断 | 需要理解内容 | 写进记忆页链接的话题页；Claude Code 用 `.claude/rules/` 路径规则在打开相关文件时加载 |

- **复发规则**：同一条 C 类规则复发两次，必须改成 A 或 B。不得再给旧条目加「补充」。
- **记忆页上限**：自动加载的记忆页（Human Preferences、每个项目的 Memory）每页不超过 8,000 字符（Node 按字符计）。超出就改成索引，整条规则移到话题页；不得压缩规则。`memory-check.mjs` 执行。
- **交付门**：有交付物的项目，交付前要三份回执：项目检查器通过、Gate 清单全勾、由交付门脚本调用的不同家族独立审查。通用脚本：`Coordination/tools/deliver-gate.mjs`、`write-guard.mjs`。
- **Skill**：只放专项工具包。日常规则不做成 Skill；多步机械流程写成一条脚本命令。
- **衡量**：只看人类纠正次数和复发数（`correction-rate.mjs`），不看规则数。
