create or replace function private.marketing_global_search_impl(p_query text,p_limit_per_category integer default 8)
returns table(category text,title text,subtitle text,href text,sort_rank integer)
language plpgsql security definer set search_path=''
as $$
declare q text:=trim(coalesce(p_query,''));lim integer:=greatest(1,least(coalesce(p_limit_per_category,8),20));
begin
  if length(q)<2 or not private.has_permission('view_customers') then return; end if;
  return query
  select 'Marketing'::text,s.name::text,concat_ws(' • ',replace(s.category,'_',' '),case when s.active then 'Active' else 'Inactive' end)::text,'/marketing'::text,15
  from public.marketing_sources s
  where concat_ws(' ',s.name,s.category) ilike '%'||q||'%'
  order by case when s.name ilike q||'%' then 0 else 1 end,s.name
  limit lim;
end;
$$;

create or replace function public.global_system_search(p_query text,p_limit_per_category integer default 8)
returns table(category text,title text,subtitle text,href text,sort_rank integer)
language plpgsql security invoker set search_path=''
as $$
begin
  return query
  select * from (
    select * from private.global_system_search_impl(p_query,p_limit_per_category)
    union all
    select * from private.marketing_global_search_impl(p_query,p_limit_per_category)
  ) r
  order by r.sort_rank,r.category,r.title;
end;
$$;

revoke all on function private.marketing_global_search_impl(text,integer) from public,anon;
grant execute on function private.marketing_global_search_impl(text,integer) to authenticated;
revoke all on function public.global_system_search(text,integer) from public,anon;
grant execute on function public.global_system_search(text,integer) to authenticated;
