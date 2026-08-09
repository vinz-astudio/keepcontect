-- GM/管理员删除/封禁用户账号
create or replace function public.gm_delete_user(_target uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_admin(auth.uid()) then raise exception 'forbidden'; end if;
  
  -- Delete all associated rows to prevent foreign key constraint violations
  delete from public.clients where user_id = _target;
  delete from public.notifications where recipient_id = _target or actor_id = _target;
  delete from public.alert_signals where user_id = _target;
  delete from public.alerts where user_id = _target or paused_by = _target;
  delete from public.guardians where user_id = _target or guardian_id = _target;
  delete from public.group_members where user_id = _target;
  delete from public.checkin_tasks where user_id = _target or created_by = _target;
  
  -- Finally delete user profile
  delete from public.profiles where id = _target;
end;
$$;
grant execute on function public.gm_delete_user(uuid) to authenticated;
