create table if not exists public.job_callbacks (
  id uuid primary key default gen_random_uuid(),
  original_job_id uuid not null references public.jobs(id) on delete restrict,
  callback_job_id uuid not null unique references public.jobs(id) on delete restrict,
  original_technician_id uuid references public.users(id),
  reason text not null default 'unknown' check (reason in ('workmanship','material_failure','customer_change','scope_exclusion','diagnostic_return','unknown')),
  preventability text not null default 'pending' check (preventability in ('pending','preventable','not_preventable','mixed')),
  callback_cost numeric not null default 0 check (callback_cost >= 0),
  manager_note text,
  reviewed_by uuid references public.users(id), reviewed_at timestamptz,
  created_by uuid not null references public.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint job_callbacks_distinct_jobs check (original_job_id <> callback_job_id)
);
create index if not exists job_callbacks_original_job_idx on public.job_callbacks(original_job_id);
create index if not exists job_callbacks_original_tech_idx on public.job_callbacks(original_technician_id);
alter table public.job_callbacks enable row level security;
revoke all on table public.job_callbacks from anon, authenticated;

create or replace function public.record_job_callback(p_original_job_id uuid,p_callback_job_id uuid,p_reason text default 'unknown',p_manager_note text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_role text; v_original public.jobs%rowtype; v_id uuid;
begin
 select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
 if v_actor is null then raise exception 'Employee identity unavailable'; end if;
 if v_role not in ('owner','manager') and not public.has_permission_for_current_user('manage_jobs') then raise exception 'Manager job permission required'; end if;
 if p_reason not in ('workmanship','material_failure','customer_change','scope_exclusion','diagnostic_return','unknown') then raise exception 'Invalid callback reason'; end if;
 select * into v_original from public.jobs where id=p_original_job_id; if not found then raise exception 'Original job not found'; end if;
 if not exists(select 1 from public.jobs where id=p_callback_job_id) then raise exception 'Callback job not found'; end if;
 insert into public.job_callbacks(original_job_id,callback_job_id,original_technician_id,reason,manager_note,created_by)
 values(p_original_job_id,p_callback_job_id,v_original.technician_id,p_reason,nullif(btrim(coalesce(p_manager_note,'')),''),v_actor)
 on conflict(callback_job_id) do update set original_job_id=excluded.original_job_id,original_technician_id=excluded.original_technician_id,reason=excluded.reason,manager_note=excluded.manager_note,updated_at=now() returning id into v_id;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'record_job_callback','job_callback',v_id::text,jsonb_build_object('original_job_id',p_original_job_id,'callback_job_id',p_callback_job_id,'reason',p_reason)); return v_id;
end;$$;

create or replace function public.review_job_callback(p_callback_id uuid,p_preventability text,p_callback_cost numeric default 0,p_manager_note text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_role text;
begin
 select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
 if v_actor is null then raise exception 'Employee identity unavailable'; end if; if v_role not in ('owner','manager') then raise exception 'Owner or manager review required'; end if;
 if p_preventability not in ('preventable','not_preventable','mixed') then raise exception 'Invalid preventability'; end if; if coalesce(p_callback_cost,0)<0 then raise exception 'Callback cost cannot be negative'; end if;
 update public.job_callbacks set preventability=p_preventability,callback_cost=coalesce(p_callback_cost,0),manager_note=coalesce(nullif(btrim(coalesce(p_manager_note,'')),''),manager_note),reviewed_by=v_actor,reviewed_at=now(),updated_at=now() where id=p_callback_id; if not found then raise exception 'Callback record not found'; end if;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'review_job_callback','job_callback',p_callback_id::text,jsonb_build_object('preventability',p_preventability,'callback_cost',coalesce(p_callback_cost,0))); return p_callback_id;
end;$$;

create or replace function public.technician_callback_snapshot(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid; v_role text; v_since timestamptz:=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),365))); v_result jsonb;
begin
 select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true limit 1; if v_actor is null then raise exception 'Employee identity unavailable'; end if;
 if v_role<>'technician' and not public.has_permission_for_current_user('view_team') then raise exception 'Team permission required'; end if;
 select coalesce(jsonb_agg(x order by x."callbackRate" desc),'[]'::jsonb) into v_result from (
  select u.id "technicianId",u.name,count(distinct j.id)::int "completedJobs",count(distinct c.id)::int callbacks,count(distinct c.id) filter(where c.preventability='preventable')::int "preventableCallbacks",coalesce(sum(c.callback_cost),0) "callbackCost",case when count(distinct j.id)>0 then round(count(distinct c.id)::numeric/count(distinct j.id)*100,1) else 0 end "callbackRate"
  from public.users u left join public.jobs j on j.technician_id=u.id and j.completed_at>=v_since left join public.job_callbacks c on c.original_job_id=j.id and c.created_at>=v_since
  where u.role='technician' and u.active=true and (v_role<>'technician' or u.id=v_actor) group by u.id,u.name
 ) x; return v_result;
end;$$;
revoke execute on function public.record_job_callback(uuid,uuid,text,text) from public,anon;
revoke execute on function public.review_job_callback(uuid,text,numeric,text) from public,anon;
revoke execute on function public.technician_callback_snapshot(integer) from public,anon;
grant execute on function public.record_job_callback(uuid,uuid,text,text), public.review_job_callback(uuid,text,numeric,text), public.technician_callback_snapshot(integer) to authenticated;