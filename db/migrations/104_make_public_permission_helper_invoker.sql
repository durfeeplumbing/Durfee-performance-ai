revoke all on function private.has_permission(text) from anon,public;
grant usage on schema private to authenticated;
grant execute on function private.has_permission(text) to authenticated;

create or replace function public.has_permission_for_current_user(p_key text)
returns boolean
language sql
stable
security invoker
set search_path=''
as $$ select private.has_permission(p_key) $$;

revoke all on function public.has_permission_for_current_user(text) from anon,public;
grant execute on function public.has_permission_for_current_user(text) to authenticated;
