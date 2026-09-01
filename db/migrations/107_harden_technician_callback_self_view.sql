create or replace function private.technician_callback_snapshot(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid;
  v_role text;
  v_since timestamptz := now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),365)));
  v_result jsonb;
begin
  select id,role into v_actor,v_role
  from public.users
  where auth_user_id=auth.uid() and active=true
  limit 1;

  if v_actor is null then
    raise exception 'Employee identity unavailable';
  end if;

  if v_role='technician' then
    select coalesce(jsonb_agg(x),'[]'::jsonb) into v_result
    from (
      select
        u.id "technicianId",
        u.name,
        count(distinct j.id)::int "completedJobs",
        count(distinct c.id)::int callbacks,
        count(distinct c.id) filter(where c.preventability='preventable')::int "preventableCallbacks",
        null::numeric "callbackCost",
        case when count(distinct j.id)>0
          then round(count(distinct c.id)::numeric/count(distinct j.id)*100,1)
          else 0 end "callbackRate"
      from public.users u
      left join public.jobs j
        on j.technician_id=u.id
       and j.completed_at>=v_since
      left join public.job_callbacks c
        on c.original_job_id=j.id
       and c.created_at>=v_since
       and c.reviewed_at is not null
      where u.id=v_actor
      group by u.id,u.name
    ) x;
  else
    if not public.has_permission_for_current_user('view_team') then
      raise exception 'Team permission required';
    end if;

    select coalesce(jsonb_agg(x order by x."callbackRate" desc),'[]'::jsonb) into v_result
    from (
      select
        u.id "technicianId",
        u.name,
        count(distinct j.id)::int "completedJobs",
        count(distinct c.id)::int callbacks,
        count(distinct c.id) filter(where c.preventability='preventable')::int "preventableCallbacks",
        coalesce(sum(c.callback_cost),0) "callbackCost",
        case when count(distinct j.id)>0
          then round(count(distinct c.id)::numeric/count(distinct j.id)*100,1)
          else 0 end "callbackRate"
      from public.users u
      left join public.jobs j
        on j.technician_id=u.id
       and j.completed_at>=v_since
      left join public.job_callbacks c
        on c.original_job_id=j.id
       and c.created_at>=v_since
       and c.reviewed_at is not null
      where u.role='technician' and u.active=true
      group by u.id,u.name
    ) x;
  end if;

  return v_result;
end;
$$;

revoke all on function private.technician_callback_snapshot(integer) from public, anon, authenticated;
grant execute on function private.technician_callback_snapshot(integer) to postgres;

create or replace function public.technician_callback_snapshot(p_days integer default 30)
returns jsonb
language sql
stable
set search_path=''
as $$select private.technician_callback_snapshot($1)$$;

revoke all on function public.technician_callback_snapshot(integer) from public, anon;
grant execute on function public.technician_callback_snapshot(integer) to authenticated;
