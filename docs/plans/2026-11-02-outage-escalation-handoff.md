# Keep Contact 任务交接：设备联系不上的告警不得升到 terminal（人类已选方案 A）

- **交接日期**：2026-11-02
- **来源**：Antigravity（根据本地 Obsidian 2nd Brain 真实记忆与仓库现场为 Claude 整理）
- **目标会话**：Claude 桌面端「Keep Contact 修复任务交接」
- **状态**：待实现（Open）

---

## 一、任务目标与决策背景

### 1. 核心目标
- 对于 `miss_kind = 'device_unreachable'` 的沉默告警，阶段升级**最多升到 `group` 或 `community`，绝不得升到 `terminal`**。
- **不得解锁用户的家庭地址与紧急联系人资料**。
- `silent`（人身真实无动静）告警行为保持现状不变（仍可升级至 terminal 并解锁资料）。

### 2. 决策与原话（人类 2026-11-02）
- 人类已于 2026-11-02 明确选择 **方案 A**（原话：「A」，已记录在 `Projects/Keep Contact/Decisions.md` 快记中）。
- **业务理由**：设备没电或拔电（`device_off`）不是人身失联。
  - 生产近 30 天 31 条 cause=silence 告警中，100% 分类为 `device_unreachable`。
  - 其中多达 6 条一路升级到 `terminal`，向真实紧急联系人发出了“已为你解锁其地址与紧急联系人，请上门探视或协助报警”的误警报。
  - 违背了 ADR-0040 修订一（`device_off` 不得判为人身失联）与 ADR-0039 修订一（只允许贯穿至 group / community，措辞须为“KC 失去联系”）。

---

## 二、当前 Git 仓库状态与环境隔离

1. **基础分支**：`test/sql-replay-production-acl`（已推送到 `origin`）。
2. **HEAD 提交**：`ee86410`（2026-10-30 `fix(sql): prune pg_cron history and read the job-health window once`）。
3. **已包含的 3 个关键提交**（比 `origin/main` 领先，main 尚未合并）：
   - `ee86410`：pg_cron 历史清理，解决 10-30 生产 Nano 实例卡死问题；
   - `878ae50`：补齐内部 RPC EXECUTE 权限回收测试（21/21 PASS）；
   - `f3bed38`：本地重放挂载生产权限快照（53/53 pgTAP PASS），并修正 3 个历史过期断言。
4. **工作区脏文件警告（重要）**：
   - 本地工作区当前包含 7 个**未提交修改**：`AGENTS.md`、`CLAUDE.md`、`src/features/legal/PrivacyPolicy.tsx`、`src/features/passive/GuardianPermissionsCard.tsx`、`src/features/passive/guardianPermissions.ts`、`src/features/passive/native.ts`、`vercel.json`。
   - 这些属于另一个进行中的商店合规/隐私政策任务，**切勿覆盖、混入、还原或提交这 7 个文件**！新工作请切出新分支或仅修改数据库迁移/测试相关文件。

---

## 三、代码入口与逻辑现状（经代码原件核对）

### 1. 阶段升级推进引擎：`public.process_escalations()`
- **文件位置**：`supabase/migrations/20260923054905_activity_auto_resolution_guardian_pattern.sql`（第 287–375 行）。
- **当前逻辑片段**：
  ```sql
  FOR r IN SELECT * FROM public.alerts a WHERE status='open' AND next_deadline IS NOT NULL
    AND next_deadline<=now() AND coalesce(paused_until,to_timestamp(0))<=now()
    AND (NOT EXISTS(SELECT 1 FROM private.passive_alert_causal_windows c WHERE c.alert_id=a.id)
      OR NOT EXISTS(
        SELECT 1 FROM public.passive_checkin_accounts p
        WHERE p.user_id=a.user_id AND private.passive_sleep_relaxed(a.user_id,p.active_contract_version_id,now())
      ))
  LOOP BEGIN
    PERFORM private.resolve_activity_alerts(r.user_id);
    _new:=CASE r.stage WHEN 'self' THEN 'group' WHEN 'group' THEN 'community'
      WHEN 'community' THEN 'terminal' ELSE 'terminal' END;
    UPDATE public.alerts SET stage=_new,stage_entered_at=now(),paused_until=NULL,paused_by=NULL,
      updated_at=now(),next_deadline=CASE _new WHEN 'group' THEN now()+_group_dur
        WHEN 'community' THEN now()+_comm_dur ELSE NULL END WHERE id=r.id AND status='open' AND stage=r.stage;
    IF NOT FOUND THEN CONTINUE; END IF;
    INSERT INTO public.alert_events(alert_id,kind,note) VALUES(r.id,'escalated',_new);
    PERFORM private.notify_stage(r.id,r.user_id,_new); _triggered:=true;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO private.job_failures(job_name,subject_id,sqlstate,message)
    VALUES('process_escalations',r.user_id,SQLSTATE,SQLERRM);
  END; END LOOP;
  ```
- **修改要点**：
  - 判断告警是否为 `miss_kind = 'device_unreachable'`。
  - 若是 `device_unreachable`，当其处于 `community`（或达到封顶阶段）时，**禁止升级到 `terminal`**，且其 `next_deadline` 应当清空为 `NULL`（停止继续计时升级）。

### 2. 因果窗口与 miss_kind 查询方式
- `public.passive_checkin_windows.miss_kind`。
- 通过 `private.passive_alert_causal_windows` 关联到 `alert_id`，取 `ordinal` 最大的因果窗口获取当前 `miss_kind`（与 `notify_stage` 中逻辑一致）：
  ```sql
  SELECT causal_window.miss_kind INTO _kind
  FROM private.passive_alert_causal_windows AS causal
  JOIN public.passive_checkin_windows AS causal_window ON causal_window.id = causal.window_id
  WHERE causal.alert_id = _alert_id
  ORDER BY causal_window.ordinal DESC LIMIT 1;
  ```

### 3. 通知文案与分发：`private.notify_stage`
- **文件位置**：`supabase/migrations/20260920000000_proactive_care_and_safe_ack.sql`（第 52–139 行）。
- 当前已对 `device_unreachable` 的 group 与 community 阶段定制了文案（如 `_name||' 的设备与 KC 失去联系，可能已关机或没电。请尝试联系本人确认。'`）。需检查是否有需要同步适配的逻辑分支。

### 4. 隐私资料解锁防护（Address & Emergency Contacts）
- **数据表**：`public.emergency_info`（包含 `home_address`, `medical_notes`, `emergency_contact_name`, `emergency_contact_phone`, `latitude`, `longitude` 等）。
- **RLS 策略**：`emergency_info_select`（`20260808160000_baseline_from_production.sql:10814` 附近）：
  ```sql
  CREATE POLICY "emergency_info_select" ON "public"."emergency_info" FOR SELECT TO "authenticated"
  USING (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR ((EXISTS ( SELECT 1
    WHERE (("a"."user_id" = "emergency_info"."user_id") AND ("a"."status" = 'open'::"text")
      AND (("a"."stage" = 'terminal'::"text") OR ("a"."cause" = 'sos'::"text")))))
    AND ("private"."is_guardian_of"("user_id", ( SELECT "auth"."uid"() AS "uid"))
      OR "private"."watches_user"(( SELECT "auth"."uid"() AS "uid"), "user_id")
      OR "private"."shares_community"(( SELECT "auth"."uid"() AS "uid"), "user_id")))));
  ```
- **确认点**：只要告警无法晋升到 `stage = 'terminal'`，RLS 便不会放行查询。但需进一步审查全库函数（如 `private.can_see_alert` 等），确认没有其他绕过机制在非 terminal 阶段泄漏资料。

---

## 四、Obsidian 2nd Brain 必守规则与记忆约束

1. **M2 · 本地库不等于生产库**：仓库迁移单独无法复现生产 GRANT/REVOKE，本地使用生产权限快照（`scripts/local-replay-production-acl.mjs`）。
2. **M3 · 共享本地容器**：本地若有共用容器 `supabase_db_Keep_contact`，切勿执行破坏性 `db reset`。
3. **M4 · pgTAP 跨语句比对要锁快照**：本地定时 cron 会在事务外改表，跨语句比对断言在 `BEGIN;` 后立刻执行 `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;`。
4. **M6 · `notify_stage` 是分发器**：改动前使用 `grep -rln "失去联系" supabase/migrations/` 找最新定义，禁止从 baseline 抄写旧逻辑。
5. **M7 · 改判断引擎前造旧状态 fixture**：必须先写出重现缺陷的失败测试（如构造一个 `device_unreachable` 告警在 `community` 到期后不进入 `terminal` 且资料不可见；同时验证 `silent` 正常进入 `terminal`）。
6. **M13 · 画像（Profile）契约**：KC 的 Profile 即为「账户画像」，不是单独文件，决定链见 ADR-0035 → ADR-0045。
7. **L3 · iOS 后台定位禁止恢复**：这是人类明确决定的设计，绝对禁止自行恢复 iOS 后台定位。
8. **增量追加迁移**：采用 append-only 迁移方式（新建一个以当前 UTC 时间戳命名的 migration 文件），严禁修改已发布的旧 migration 文件。

---

## 五、必须暂停并向人类确认的检查点（Checkpoints）

1. **`collection_restricted` 范围确认**：人类目前仅明确授权封顶 `device_unreachable`，**不得自行扩大**到 `collection_restricted`（采集被关/权限丢失）。
2. **生产操作拦截**：严禁自行执行生产数据库迁移部署、Edge Function 发布或直接合并至 `origin/main`。上线前必须提供精确 diff、完整测试通过证据并等待人类明确审批。
3. **存量告警处理**：对生产已处于 terminal 阶段的历史 `device_unreachable` 告警是否需要写一次性数据修正。

---

## 六、本地验证命令参考（Windows / Podman 环境）

```bash
export MSYS_NO_PATHCONV=1
podman machine start
node -e "import('./scripts/local-supabase-replay-core.mjs').then(m=>m.prepareReplayProject({repoRoot:process.cwd()}))"
podman run -d --name kc-sqltest --network none -e POSTGRES_PASSWORD=test public.ecr.aws/supabase/postgres:17.6.1.159
# 等待容器启动约 25 秒
podman exec -u root kc-sqltest sh -c 'mkdir -p /work && chmod 777 /work'
podman cp supabase/.temp/replay-compat/project/supabase/. kc-sqltest:/work/
podman exec -u root kc-sqltest chmod -R a+rX /work

# 按文件名顺序执行重放迁移（包含生产权限快照）
podman exec kc-sqltest sh -c 'cd /work/migrations && for f in $(ls | sort); do psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -f "$f" || { echo FAIL $f; exit 1; }; done; echo REPLAY_OK'

# 修复 auth.uid()（镜像默认只读 claim.sub，测试写 claims）
# 注意使用 -i 交互模式
podman exec -i kc-sqltest psql -U supabase_admin -d postgres << 'EOF'
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid;
$$;
EOF

# 运行 pgTAP 测试
podman exec kc-sqltest psql -U postgres -d postgres -c 'create extension if not exists pgtap with schema extensions;'
# 执行测试文件并统计 ok / not ok
```
