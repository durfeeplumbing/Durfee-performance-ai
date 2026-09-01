create table if not exists public.marketing_unmatched_calls (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'dialpad',
  provider_event_id text,
  from_address text,
  to_address text,
  occurred_at timestamptz not null,
  duration_seconds integer,
  status text,
  touchpoint_id uuid references public.marketing_touchpoints(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  job_id uuid references public.jobs(id) on delete set null,
  match_status text not null default 'unmatched' check(match_status in ('unmatched','touchpoint_matched','customer_matched','job_matched','ignored')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.marketing_unmatched_calls enable row level security;
revoke all on public.marketing_unmatched_calls from anon,authenticated;
grant select,insert,update,delete on public.marketing_unmatched_calls to service_role;
create unique index if not exists marketing_unmatched_calls_provider_event_uidx on public.marketing_unmatched_calls(provider,provider_event_id) where provider_event_id is not null;
create index if not exists marketing_unmatched_calls_touchpoint_idx on public.marketing_unmatched_calls(touchpoint_id,occurred_at desc) where touchpoint_id is not null;
create index if not exists marketing_unmatched_calls_customer_idx on public.marketing_unmatched_calls(customer_id,occurred_at desc) where customer_id is not null;
create index if not exists marketing_unmatched_calls_job_idx on public.marketing_unmatched_calls(job_id) where job_id is not null;

create or replace function private.record_unmatched_marketing_call_impl(p_provider_event_id text,p_from_address text,p_to_address text,p_occurred_at timestamptz,p_duration_seconds integer,p_status text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_touch uuid;v_assignment uuid;v_customer uuid;v_job uuid;v_event uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 select a.touchpoint_id,a.id into v_touch,v_assignment
 from public.marketing_tracking_assignments a join public.marketing_tracking_numbers n on n.id=a.tracking_number_id
 where private.normalize_marketing_phone(n.phone_number)=private.normalize_marketing_phone(p_to_address)
   and a.assigned_at<=coalesce(p_occurred_at,now()) and a.expires_at>=coalesce(p_occurred_at,now())-interval '5 minutes'
 order by a.assigned_at desc limit 1;
 if v_touch is not null then select customer_id,job_id into v_customer,v_job from public.marketing_touchpoints where id=v_touch; end if;
 insert into public.marketing_unmatched_calls(provider,provider_event_id,from_address,to_address,occurred_at,duration_seconds,status,touchpoint_id,customer_id,job_id,match_status,updated_at)
 values('dialpad',nullif(trim(coalesce(p_provider_event_id,'')),''),nullif(trim(coalesce(p_from_address,'')),''),nullif(trim(coalesce(p_to_address,'')),''),coalesce(p_occurred_at,now()),p_duration_seconds,nullif(trim(coalesce(p_status,'')),''),v_touch,v_customer,v_job,case when v_job is not null then 'job_matched' when v_customer is not null then 'customer_matched' when v_touch is not null then 'touchpoint_matched' else 'unmatched' end,now())
 on conflict(provider,provider_event_id) where provider_event_id is not null do update set from_address=excluded.from_address,to_address=excluded.to_address,occurred_at=excluded.occurred_at,duration_seconds=excluded.duration_seconds,status=excluded.status,touchpoint_id=coalesce(public.marketing_unmatched_calls.touchpoint_id,excluded.touchpoint_id),customer_id=coalesce(public.marketing_unmatched_calls.customer_id,excluded.customer_id),job_id=coalesce(public.marketing_unmatched_calls.job_id,excluded.job_id),match_status=case when coalesce(public.marketing_unmatched_calls.job_id,excluded.job_id) is not null then 'job_matched' when coalesce(public.marketing_unmatched_calls.customer_id,excluded.customer_id) is not null then 'customer_matched' when coalesce(public.marketing_unmatched_calls.touchpoint_id,excluded.touchpoint_id) is not null then 'touchpoint_matched' else 'unmatched' end,updated_at=now()
 returning id into v_id;
 if v_touch is not null then
  update public.marketing_tracking_assignments set last_used_at=coalesce(p_occurred_at,now()) where id=v_assignment;
  update public.marketing_touchpoints set last_seen_at=greatest(last_seen_at,coalesce(p_occurred_at,now())) where id=v_touch;
  v_event:=private.record_marketing_conversion_impl(v_touch,v_customer,v_job,null,null,'call',coalesce(p_occurred_at,now()),0,'USD','call-unmatched:'||v_id::text);
 end if;
 return v_id;
end$$;

create or replace function public.record_unmatched_marketing_call(p_provider_event_id text,p_from_address text,p_to_address text,p_occurred_at timestamptz,p_duration_seconds integer default null,p_status text default null)
returns uuid language sql security definer set search_path='' as $$ select private.record_unmatched_marketing_call_impl(p_provider_event_id,p_from_address,p_to_address,p_occurred_at,p_duration_seconds,p_status) $$;
revoke all on function public.record_unmatched_marketing_call(text,text,text,timestamptz,integer,text) from public,anon,authenticated;
grant execute on function public.record_unmatched_marketing_call(text,text,text,timestamptz,integer,text) to service_role;

create or replace function public.marketing_unmatched_call_queue(p_days integer default 30,p_limit integer default 100)
returns table(id uuid,occurred_at timestamptz,from_address text,to_address text,duration_seconds integer,status text,match_status text,touchpoint_id uuid,customer_id uuid,job_id uuid)
language sql stable set search_path='' as $$
 select c.id,c.occurred_at,c.from_address,c.to_address,c.duration_seconds,c.status,c.match_status,c.touchpoint_id,c.customer_id,c.job_id
 from public.marketing_unmatched_calls c
 where (public.has_permission_for_current_user('view_csr') or public.has_permission_for_current_user('view_reports')) and c.occurred_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650)))
 order by case c.match_status when 'unmatched' then 0 when 'touchpoint_matched' then 1 else 2 end,c.occurred_at desc limit greatest(1,least(coalesce(p_limit,100),500));
$$;
revoke all on function public.marketing_unmatched_call_queue(integer,integer) from public,anon;
grant execute on function public.marketing_unmatched_call_queue(integer,integer) to authenticated;