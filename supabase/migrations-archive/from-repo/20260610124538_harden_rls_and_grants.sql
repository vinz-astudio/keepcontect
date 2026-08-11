-- 加固：收紧 RLS WITH CHECK、撤销触发器函数的 RPC 可执行权限、补外键索引
-- 回应 supabase advisors（security WARN + performance INFO）

------------------------------------------------------------
-- 1. 触发器函数不应作为 RPC 端点暴露：撤销所有 EXECUTE
--    （触发器以表属主身份执行，不依赖这些 grant）
------------------------------------------------------------
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_new_community() from public, anon, authenticated;
revoke execute on function public.handle_new_group() from public, anon, authenticated;

------------------------------------------------------------
-- 2. UPDATE 策略的 WITH CHECK 从 true 收紧为与 USING 相同的 admin 谓词
--    防止管理员把行改成不再满足约束的状态
------------------------------------------------------------
alter policy communities_update on public.communities
  with check (
    exists (
      select 1 from public.community_members cm
      where cm.community_id = communities.id and cm.user_id = (select auth.uid())
        and cm.role = 'admin' and cm.status = 'active'
    )
  );

alter policy groups_update on public.groups
  with check (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = groups.id and gm.user_id = (select auth.uid())
        and gm.role = 'admin' and gm.status = 'active'
    )
  );

------------------------------------------------------------
-- 3. 补 created_by 外键的覆盖索引
------------------------------------------------------------
create index if not exists communities_created_by_idx on public.communities (created_by);
create index if not exists groups_created_by_idx on public.groups (created_by);
