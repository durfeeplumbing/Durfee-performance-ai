create table if not exists public.customer_communications (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete set null,
  booked_job_id uuid references public.jobs(id) on delete set null,
  channel text not null check (channel in ('phone','sms','email')),
  direction text not null check (direction in ('inbound','outbound')),
  event_type text not null check (event_type in ('message','call')),
  status text not null default 'queued' check (status in ('queued','sent','delivered','failed','received','missed','completed','canceled')),
  from_address text,to_address text,subject text,body text,provider text,provider_event_id text,
  occurred_at timestamptz not null default now(),duration_seconds integer check (duration_seconds is null or duration_seconds>=0),
  recording_url text,transcript text,ai_summary text,disposition text,
  booking_outcome text not null default 'none' check (booking_outcome in ('none','booked','not_booked','follow_up')),
  handled_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists customer_communications_provider_event_uidx on public.customer_communications(provider,provider_event_id) where provider is not null and provider_event_id is not null;
create index if not exists customer_communications_customer_occurred_idx on public.customer_communications(customer_id,occurred_at desc);
create index if not exists customer_communications_job_occurred_idx on public.customer_communications(job_id,occurred_at desc) where job_id is not null;
create index if not exists customer_communications_status_channel_idx on public.customer_communications(status,channel,occurred_at desc);
create index if not exists customer_communications_handled_by_idx on public.customer_communications(handled_by);
create index if not exists customer_communications_booked_job_idx on public.customer_communications(booked_job_id) where booked_job_id is not null;
alter table public.customer_communications enable row level security;
revoke all on public.customer_communications from public,anon,authenticated;

create or replace function private.communication_access_allowed(p_manage boolean default false) returns boolean language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then return false; end if;
  if exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.active and u.role in ('owner','manager')) then return true; end if;
  if p_manage then return coalesce(public.has_permission_for_current_user('manage_csr'),false); end if;
  return coalesce(public.has_permission_for_current_user('view_csr'),false) or coalesce(public.has_permission_for_current_user('view_customers'),false);
end;$$;
revoke all on function private.communication_access_allowed(boolean) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.communication_access_allowed(boolean) to authenticated;

create or replace function private.customer_communication_inbox(p_days integer default 30) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_days integer:=greatest(1,least(coalesce(p_days,30),365)); v_result jsonb;
begin
  if not private.communication_access_allowed(false) then raise exception 'Communications permission required'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x."occurredAt" desc),'[]'::jsonb) into v_result from (
    select cc.id as "communicationId",cc.customer_id as "customerId",c.name as "customerName",c.phone as "customerPhone",c.email as "customerEmail",cc.job_id as "jobId",j.service_type as "serviceType",cc.channel,cc.direction,cc.event_type as "eventType",cc.status,cc.from_address as "fromAddress",cc.to_address as "toAddress",cc.subject,cc.body,cc.occurred_at as "occurredAt",cc.duration_seconds as "durationSeconds",cc.ai_summary as "aiSummary",cc.disposition,cc.booking_outcome as "bookingOutcome",cc.booked_job_id as "bookedJobId",u.name as "handledByName",
      case when exists(select 1 from public.users me where me.auth_user_id=auth.uid() and me.active and me.role in ('owner','manager')) or coalesce(public.has_permission_for_current_user('manage_csr'),false) then cc.transcript else null end as transcript,
      case when exists(select 1 from public.users me where me.auth_user_id=auth.uid() and me.active and me.role in ('owner','manager')) or coalesce(public.has_permission_for_current_user('manage_csr'),false) then cc.recording_url else null end as "recordingUrl"
    from public.customer_communications cc join public.customers c on c.id=cc.customer_id left join public.jobs j on j.id=cc.job_id left join public.users u on u.id=cc.handled_by
    where cc.occurred_at>=now()-(v_days||' days')::interval
  ) x; return v_result;
end;$$;
create or replace function public.customer_communication_inbox(p_days integer default 30) returns jsonb language sql security invoker set search_path='' as $$select private.customer_communication_inbox(p_days);$$;
revoke all on function public.customer_communication_inbox(integer) from public,anon;
grant execute on function public.customer_communication_inbox(integer) to authenticated;
revoke all on function private.customer_communication_inbox(integer) from public,anon;
grant execute on function private.customer_communication_inbox(integer) to authenticated;

create or replace function private.queue_customer_communication(p_customer_id uuid,p_job_id uuid,p_channel text,p_to text,p_subject text default null,p_body text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_actor uuid;v_from text;
begin
  if not private.communication_access_allowed(true) then raise exception 'Communications management permission required'; end if;
  if p_channel not in ('sms','email','phone') then raise exception 'Unsupported channel'; end if;
  if coalesce(length(trim(p_to)),0)<3 then raise exception 'Destination required'; end if;
  if p_channel in ('sms','email') and coalesce(length(trim(p_body)),0)=0 then raise exception 'Message body required'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active limit 1;
  if not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer not found'; end if;
  if p_job_id is not null and not exists(select 1 from public.jobs where id=p_job_id and customer_id=p_customer_id) then raise exception 'Job/customer mismatch'; end if;
  v_from:=case p_channel when 'email' then 'company-email' when 'sms' then 'company-sms' else 'company-phone' end;
  insert into public.customer_communications(customer_id,job_id,channel,direction,event_type,status,from_address,to_address,subject,body,handled_by)
  values(p_customer_id,p_job_id,p_channel,'outbound',case when p_channel='phone' then 'call' else 'message' end,'queued',v_from,trim(p_to),nullif(trim(coalesce(p_subject,'')),''),nullif(trim(coalesce(p_body,'')),''),v_actor) returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'queue_customer_communication','customer_communication',v_id::text,jsonb_build_object('channel',p_channel,'customer_id',p_customer_id,'job_id',p_job_id));
  return v_id;
end;$$;
create or replace function public.queue_customer_communication(p_customer_id uuid,p_job_id uuid,p_channel text,p_to text,p_subject text default null,p_body text default null) returns uuid language sql security invoker set search_path='' as $$select private.queue_customer_communication(p_customer_id,p_job_id,p_channel,p_to,p_subject,p_body);$$;
revoke all on function public.queue_customer_communication(uuid,uuid,text,text,text,text) from public,anon;
grant execute on function public.queue_customer_communication(uuid,uuid,text,text,text,text) to authenticated;
revoke all on function private.queue_customer_communication(uuid,uuid,text,text,text,text) from public,anon;
grant execute on function private.queue_customer_communication(uuid,uuid,text,text,text,text) to authenticated;

-- Provider callbacks and manual imports use this normalized writer after server-side signature/auth checks.
create or replace function private.record_customer_communication(p_customer_id uuid,p_job_id uuid,p_channel text,p_direction text,p_event_type text,p_status text,p_from text,p_to text,p_subject text,p_body text,p_occurred_at timestamptz default now(),p_duration_seconds integer default null,p_provider text default null,p_provider_event_id text default null,p_recording_url text default null,p_transcript text default null,p_ai_summary text default null,p_disposition text default null,p_booking_outcome text default 'none',p_booked_job_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_actor uuid;
begin
  if not private.communication_access_allowed(true) then raise exception 'Communications management permission required'; end if;
  if p_channel not in ('phone','sms','email') or p_direction not in ('inbound','outbound') or p_event_type not in ('message','call') then raise exception 'Invalid communication type'; end if;
  if p_status not in ('queued','sent','delivered','failed','received','missed','completed','canceled') then raise exception 'Invalid status'; end if;
  if coalesce(p_booking_outcome,'none') not in ('none','booked','not_booked','follow_up') then raise exception 'Invalid booking outcome'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active limit 1;
  if not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer not found'; end if;
  if p_job_id is not null and not exists(select 1 from public.jobs where id=p_job_id and customer_id=p_customer_id) then raise exception 'Job/customer mismatch'; end if;
  if p_booked_job_id is not null and not exists(select 1 from public.jobs where id=p_booked_job_id and customer_id=p_customer_id) then raise exception 'Booked job/customer mismatch'; end if;
  insert into public.customer_communications(customer_id,job_id,booked_job_id,channel,direction,event_type,status,from_address,to_address,subject,body,provider,provider_event_id,occurred_at,duration_seconds,recording_url,transcript,ai_summary,disposition,booking_outcome,handled_by)
  values(p_customer_id,p_job_id,p_booked_job_id,p_channel,p_direction,p_event_type,p_status,p_from,p_to,p_subject,p_body,p_provider,p_provider_event_id,coalesce(p_occurred_at,now()),p_duration_seconds,p_recording_url,p_transcript,p_ai_summary,p_disposition,coalesce(p_booking_outcome,'none'),v_actor)
  on conflict(provider,provider_event_id) where provider is not null and provider_event_id is not null do update set status=excluded.status,body=coalesce(excluded.body,public.customer_communications.body),subject=coalesce(excluded.subject,public.customer_communications.subject),duration_seconds=coalesce(excluded.duration_seconds,public.customer_communications.duration_seconds),recording_url=coalesce(excluded.recording_url,public.customer_communications.recording_url),transcript=coalesce(excluded.transcript,public.customer_communications.transcript),ai_summary=coalesce(excluded.ai_summary,public.customer_communications.ai_summary),disposition=coalesce(excluded.disposition,public.customer_communications.disposition),booking_outcome=excluded.booking_outcome,booked_job_id=coalesce(excluded.booked_job_id,public.customer_communications.booked_job_id),updated_at=now() returning id into v_id;
  return v_id;
end;$$;
create or replace function public.record_customer_communication(p_customer_id uuid,p_job_id uuid,p_channel text,p_direction text,p_event_type text,p_status text,p_from text,p_to text,p_subject text,p_body text,p_occurred_at timestamptz default now(),p_duration_seconds integer default null,p_provider text default null,p_provider_event_id text default null,p_recording_url text default null,p_transcript text default null,p_ai_summary text default null,p_disposition text default null,p_booking_outcome text default 'none',p_booked_job_id uuid default null) returns uuid language sql security invoker set search_path='' as $$select private.record_customer_communication(p_customer_id,p_job_id,p_channel,p_direction,p_event_type,p_status,p_from,p_to,p_subject,p_body,p_occurred_at,p_duration_seconds,p_provider,p_provider_event_id,p_recording_url,p_transcript,p_ai_summary,p_disposition,p_booking_outcome,p_booked_job_id);$$;
revoke all on function public.record_customer_communication(uuid,uuid,text,text,text,text,text,text,text,text,timestamptz,integer,text,text,text,text,text,text,text,uuid) from public,anon;
grant execute on function public.record_customer_communication(uuid,uuid,text,text,text,text,text,text,text,text,timestamptz,integer,text,text,text,text,text,text,text,uuid) to authenticated;
revoke all on function private.record_customer_communication(uuid,uuid,text,text,text,text,text,text,text,text,timestamptz,integer,text,text,text,text,text,text,text,uuid) from public,anon;
grant execute on function private.record_customer_communication(uuid,uuid,text,text,text,text,text,text,text,text,timestamptz,integer,text,text,text,text,text,text,text,uuid) to authenticated;
