create table if not exists public.marketing_conversion_sync_queue (
  id uuid primary key default gen_random_uuid(),
  conversion_event_id uuid not null references public.marketing_conversion_events(id) on delete cascade,
  provider text not null check (provider in ('google_ads','meta_ads')),
  status text not null default 'waiting_authorization' check (status in ('not_ready','waiting_authorization','ready','processing','sent','failed','suppressed')),
  attempts integer not null default 0 check (attempts>=0),
  next_attempt_at timestamptz,
  last_attempt_at timestamptz,
  last_error text,
  provider_event_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(conversion_event_id,provider)
);
alter table public.marketing_conversion_sync_queue enable row level security;
revoke all on public.marketing_conversion_sync_queue from anon,authenticated;
grant select,insert,update,delete on public.marketing_conversion_sync_queue to service_role;
create index if not exists marketing_conversion_sync_queue_event_idx on public.marketing_conversion_sync_queue(conversion_event_id);
create index if not exists marketing_conversion_sync_queue_ready_idx on public.marketing_conversion_sync_queue(provider,status,next_attempt_at) where status in ('ready','failed','waiting_authorization');

create or replace function private.queue_marketing_conversion_sync(p_event_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare e public.marketing_conversion_events%rowtype; t public.marketing_touchpoints%rowtype;
begin
  select * into e from public.marketing_conversion_events where id=p_event_id;
  if e.id is null then return; end if;
  select * into t from public.marketing_touchpoints where id=e.touchpoint_id;
  insert into public.marketing_conversion_sync_queue(conversion_event_id,provider,status,updated_at)
  values(e.id,'google_ads',case when coalesce(t.gclid,t.gbraid,t.wbraid) is null then 'not_ready' else 'waiting_authorization' end,now())
  on conflict(conversion_event_id,provider) do update set status=case when excluded.status='not_ready' and public.marketing_conversion_sync_queue.status in ('sent','processing') then public.marketing_conversion_sync_queue.status else excluded.status end,updated_at=now();
  insert into public.marketing_conversion_sync_queue(conversion_event_id,provider,status,updated_at)
  values(e.id,'meta_ads',case when t.fbclid is null then 'not_ready' else 'waiting_authorization' end,now())
  on conflict(conversion_event_id,provider) do update set status=case when excluded.status='not_ready' and public.marketing_conversion_sync_queue.status in ('sent','processing') then public.marketing_conversion_sync_queue.status else excluded.status end,updated_at=now();
end$$;

create or replace function private.upsert_marketing_conversion(p_job_id uuid,p_invoice_id uuid,p_payment_id uuid,p_event_type text,p_event_time timestamptz,p_value numeric,p_transaction_id text)
returns void language plpgsql security definer set search_path='' as $$
declare v_touch uuid; v_customer uuid; v_id uuid; v_google text; v_meta text;
begin
  if p_job_id is null or p_transaction_id is null then return; end if;
  select customer_id into v_customer from public.jobs where id=p_job_id;
  if v_customer is null then return; end if;
  v_touch:=private.marketing_touchpoint_for_job(p_job_id,p_event_time);
  if v_touch is null then return; end if;
  select case when coalesce(gclid,gbraid,wbraid) is null then 'not_ready' else 'pending' end,
         case when fbclid is null then 'not_ready' else 'pending' end into v_google,v_meta
  from public.marketing_touchpoints where id=v_touch;
  insert into public.marketing_conversion_events(touchpoint_id,customer_id,job_id,invoice_id,payment_id,event_type,event_time,value,currency_code,transaction_id,google_upload_status,meta_upload_status)
  values(v_touch,v_customer,p_job_id,p_invoice_id,p_payment_id,p_event_type,coalesce(p_event_time,now()),greatest(coalesce(p_value,0),0),'USD',p_transaction_id,v_google,v_meta)
  on conflict(event_type,transaction_id) do update set touchpoint_id=excluded.touchpoint_id,customer_id=excluded.customer_id,job_id=excluded.job_id,invoice_id=excluded.invoice_id,payment_id=excluded.payment_id,event_time=excluded.event_time,value=excluded.value,google_upload_status=case when public.marketing_conversion_events.google_upload_status='sent' then 'sent' else excluded.google_upload_status end,meta_upload_status=case when public.marketing_conversion_events.meta_upload_status='sent' then 'sent' else excluded.meta_upload_status end
  returning id into v_id;
  perform private.queue_marketing_conversion_sync(v_id);
end$$;

create or replace function private.reconcile_marketing_job_impl(p_job_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j public.jobs%rowtype; i record; p record;
begin
  select * into j from public.jobs where id=p_job_id;
  if j.id is null then return; end if;
  perform private.upsert_marketing_conversion(j.id,null,null,'booked_job',j.created_at,0,'job-booked:'||j.id::text);
  if j.completed_at is not null then perform private.upsert_marketing_conversion(j.id,null,null,'job_completed',j.completed_at,j.revenue,'job-completed:'||j.id::text); end if;
  for i in select id,total,created_at from public.invoices where job_id=j.id loop
    perform private.upsert_marketing_conversion(j.id,i.id,null,'invoice',i.created_at,i.total,'invoice:'||i.id::text);
  end loop;
  for p in select id,amount,received_at from public.payments where job_id=j.id loop
    perform private.upsert_marketing_conversion(j.id,null,p.id,'payment',p.received_at,p.amount,'payment:'||p.id::text);
  end loop;
end$$;

create or replace function private.link_marketing_touchpoint_impl(p_touchpoint_id uuid,p_customer_id uuid default null,p_job_id uuid default null,p_communication_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare t public.marketing_touchpoints%rowtype; v_id uuid;
begin
  if p_job_id is not null and p_customer_id is not null and not exists(select 1 from public.jobs jx where jx.id=p_job_id and jx.customer_id=p_customer_id) then raise exception 'Job does not belong to customer'; end if;
  if p_communication_id is not null and p_customer_id is not null and not exists(select 1 from public.customer_communications c where c.id=p_communication_id and c.customer_id=p_customer_id) then raise exception 'Communication does not belong to customer'; end if;
  update public.marketing_touchpoints set customer_id=coalesce(p_customer_id,customer_id),job_id=coalesce(p_job_id,job_id),communication_id=coalesce(p_communication_id,communication_id),last_seen_at=now() where id=p_touchpoint_id returning * into t;
  if t.id is null then raise exception 'Touchpoint not found'; end if;
  if t.customer_id is not null then
    v_id:=private.record_marketing_conversion_impl(t.id,t.customer_id,t.job_id,null,null,'lead',coalesce(t.first_seen_at,now()),0,'USD','lead:'||t.customer_id::text||':'||t.id::text);
    perform private.queue_marketing_conversion_sync(v_id);
  end if;
  if t.job_id is not null then perform private.reconcile_marketing_job_impl(t.job_id); end if;
end$$;

create or replace function private.link_marketing_call_impl(p_communication_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.customer_communications%rowtype; v_touch uuid; v_assignment uuid; v_job uuid; v_event uuid;
begin
  select * into c from public.customer_communications where id=p_communication_id;
  if c.id is null or c.channel<>'phone' or c.direction<>'inbound' then return null; end if;
  select a.touchpoint_id,a.id into v_touch,v_assignment
  from public.marketing_tracking_assignments a join public.marketing_tracking_numbers n on n.id=a.tracking_number_id
  where private.normalize_marketing_phone(n.phone_number)=private.normalize_marketing_phone(c.to_address)
    and a.assigned_at<=c.occurred_at and a.expires_at>=c.occurred_at-interval '5 minutes'
  order by a.assigned_at desc limit 1;
  if v_touch is null then return null; end if;
  v_job:=coalesce(c.job_id,c.booked_job_id);
  update public.marketing_touchpoints set communication_id=c.id,customer_id=coalesce(customer_id,c.customer_id),job_id=coalesce(job_id,v_job),last_seen_at=greatest(last_seen_at,c.occurred_at) where id=v_touch;
  update public.marketing_tracking_assignments set last_used_at=c.occurred_at where id=v_assignment;
  v_event:=private.record_marketing_conversion_impl(v_touch,c.customer_id,v_job,null,null,'call',c.occurred_at,0,'USD','call:'||c.id::text);
  perform private.queue_marketing_conversion_sync(v_event);
  if v_job is not null then perform private.reconcile_marketing_job_impl(v_job); end if;
  return v_touch;
end$$;

create or replace function private.marketing_attribution_dashboard_impl(p_days integer default 30)
returns jsonb language sql stable security definer set search_path='' as $$
with bounds as (select current_date-greatest(1,least(coalesce(p_days,30),3650)) start_date),
spend as (select coalesce(sum(m.spend),0) spend,coalesce(sum(m.clicks),0) clicks,coalesce(sum(m.impressions),0) impressions from public.marketing_ad_daily_metrics m,bounds b where m.metric_date>=b.start_date),
conv as (
 select count(*) filter(where e.event_type='lead') leads,
 count(*) filter(where e.event_type='call') calls,
 count(*) filter(where e.event_type='booked_job') booked_jobs,
 count(*) filter(where e.event_type='job_completed') completed_jobs,
 coalesce(sum(e.value) filter(where e.event_type='job_completed'),0) earned_revenue,
 coalesce(sum(e.value) filter(where e.event_type='payment'),0) collected_revenue
 from public.marketing_conversion_events e,bounds b where e.event_time::date>=b.start_date),
diag as (select count(*) filter(where coalesce(t.gclid,t.gbraid,t.wbraid,t.fbclid) is not null) identified_touchpoints,count(*) touchpoints from public.marketing_touchpoints t,bounds b where t.first_seen_at::date>=b.start_date)
select jsonb_build_object('spend',spend.spend,'clicks',spend.clicks,'impressions',spend.impressions,'leads',conv.leads,'calls',conv.calls,'bookedJobs',conv.booked_jobs,'completedJobs',conv.completed_jobs,'earnedRevenue',conv.earned_revenue,'collectedRevenue',conv.collected_revenue,'revenue',case when conv.collected_revenue>0 then conv.collected_revenue else conv.earned_revenue end,'touchpoints',diag.touchpoints,'identifiedTouchpoints',diag.identified_touchpoints,'roas',case when spend.spend>0 then (case when conv.collected_revenue>0 then conv.collected_revenue else conv.earned_revenue end)/spend.spend else null end,'costPerBookedJob',case when conv.booked_jobs>0 then spend.spend/conv.booked_jobs else null end) from spend,conv,diag;
$$;

create or replace function public.marketing_sync_queue_summary()
returns table(provider text,status text,event_count bigint,total_value numeric,oldest_event timestamptz)
language sql stable set search_path='' as $$
 select q.provider,q.status,count(*)::bigint,coalesce(sum(e.value),0)::numeric,min(e.event_time)
 from public.marketing_conversion_sync_queue q join public.marketing_conversion_events e on e.id=q.conversion_event_id
 where public.has_permission_for_current_user('view_reports')
 group by q.provider,q.status order by q.provider,q.status;
$$;
revoke all on function public.marketing_sync_queue_summary() from public,anon;
grant execute on function public.marketing_sync_queue_summary() to authenticated;

create or replace function public.marketing_attribution_qa(p_days integer default 30)
returns jsonb language plpgsql stable set search_path='' as $$
declare v jsonb;
begin
 if not public.has_permission_for_current_user('view_reports') then raise exception 'Permission denied'; end if;
 select jsonb_build_object(
  'unlinkedIdentifiedTouchpoints',count(*) filter(where coalesce(t.gclid,t.gbraid,t.wbraid,t.fbclid) is not null and t.customer_id is null and t.first_seen_at<now()-interval '24 hours'),
  'unlinkedCalls',(select count(*) from public.customer_communications c where c.channel='phone' and c.direction='inbound' and c.occurred_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))) and not exists(select 1 from public.marketing_touchpoints mt where mt.communication_id=c.id)),
  'jobsWithoutAttribution',(select count(*) from public.jobs j where j.created_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))) and not exists(select 1 from public.marketing_touchpoints mt where mt.job_id=j.id or mt.customer_id=j.customer_id)),
  'readyGoogle',(select count(*) from public.marketing_conversion_sync_queue where provider='google_ads' and status in ('ready','waiting_authorization')),
  'readyMeta',(select count(*) from public.marketing_conversion_sync_queue where provider='meta_ads' and status in ('ready','waiting_authorization')),
  'failedSyncs',(select count(*) from public.marketing_conversion_sync_queue where status='failed')
 ) into v from public.marketing_touchpoints t where t.first_seen_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650)));
 return v;
end$$;
revoke all on function public.marketing_attribution_qa(integer) from public,anon;
grant execute on function public.marketing_attribution_qa(integer) to authenticated;

update public.marketing_conversion_events set event_type='call',transaction_id=regexp_replace(transaction_id,'^call:','call:') where event_type='phone_call';
update public.marketing_conversion_events set event_type='job_completed',transaction_id=regexp_replace(transaction_id,'^job:','job-completed:') where event_type='completed_job';
select private.queue_marketing_conversion_sync(id) from public.marketing_conversion_events;
