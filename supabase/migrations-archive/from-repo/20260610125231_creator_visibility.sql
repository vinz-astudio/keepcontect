-- 修复：创建者必须能读回自己刚创建的 community / group。
-- 否则 `INSERT ... RETURNING`（客户端 .insert().select()）在"创建者入组"AFTER 触发器
-- 生效前就触发 SELECT 策略检查而失败。加入 created_by = auth.uid() 兜底。

alter policy communities_select on public.communities
  using (
    created_by = (select auth.uid())
    or private.is_community_member(id, (select auth.uid()))
  );

alter policy groups_select on public.groups
  using (
    created_by = (select auth.uid())
    or private.is_group_member(id, (select auth.uid()))
    or (community_id is not null and private.is_community_member(community_id, (select auth.uid())))
  );
