create table if not exists public.marketing_ad_accounts (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('google_ads','meta_ads')),
  external_account_id text not null,
  account_name text,
  currency_code text,
  timezone text,
  status text not null default 'pending_authorization' check (status in ('pending_authorization','connected','paused','error')),
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(platform, external_account_id)
);

create table if not exists public.marketing_ad_entities (
  id uuid primary key default gen_random_uuid(),
  ad_account_id uuid not null references public.marketing_ad_accounts(id) on delete cascade,
  entity_type text not null check (entity_type in ('campaign','ad_group','ad_set','ad')),
  external_id text not null,
  parent_external_id text,
  name text,
  status text,
  channel text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(ad_account_id, entity_type, external_id)
);

create table if not exists public.marketing_ad_daily_metrics (
  id uuid primary key default gen_random_uuid(),
  ad_account_id uuid not null references public.marketing_ad_accounts(id) on delete cascade,
  metric_date date not null,
  campaign_external_id text,
  group_external_id text,
  ad_external_id text,
  impressions bigint not null default 0,
  clicks bigint not null default 0,
  spend numeric(14,2) not null default 0,
  provider_conversions numeric(14,4) not null default 0,
  provider_conversion_value numeric(14,2) not null default 0,
  synced_at timestamptz not null default now(),
  unique(ad_account_id, metric_date, campaign_external_id, group_external_id, ad_external_id)
);

create table if not exists public.marketing_touchpoints (
  id uuid primary key default gen_random_uuid(),
  session_key text not null,
  customer_id uuid references public.customers(id) on delete set null,
  job_id uuid references public.jobs(id) on delete set null,
  communication_id uuid references public.customer_communications(id) on delete set null,
  platform text,
  gclid text,
  gbraid text,
  wbraid text,
  fbclid text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_term text,
  utm_content text,
  landing_page text,
  referrer text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.marketing_conversion_events (
  id uuid primary key default gen_random_uuid(),
  touchpoint_id uuid references public.marketing_touchpoints(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  job_id uuid references public.jobs(id) on delete set null,
  invoice_id uuid references public.invoices(id) on delete set null,
  payment_id uuid references public.payments(id) on delete set null,
  event_type text not null check (event_type in ('lead','call','booked_job','estimate_sold','job_completed','invoice','payment','revenue_adjustment')),
  event_time timestamptz not null default now(),
  value numeric(14,2),
  currency_code text not null default 'USD',
  transaction_id text,
  google_upload_status text not null default 'not_ready' check (google_upload_status in ('not_ready','ready','uploaded','failed','not_applicable')),
  meta_upload_status text not null default 'not_ready' check (meta_upload_status in ('not_ready','ready','uploaded','failed','not_applicable')),
  provider_error text,
  created_at timestamptz not null default now(),
  unique(event_type, transaction_id)
);

create index if not exists marketing_touchpoints_customer_idx on public.marketing_touchpoints(customer_id, first_seen_at desc);
create index if not exists marketing_touchpoints_job_idx on public.marketing_touchpoints(job_id, first_seen_at desc);
create index if not exists marketing_touchpoints_communication_idx on public.marketing_touchpoints(communication_id);
create index if not exists marketing_touchpoints_session_idx on public.marketing_touchpoints(session_key, first_seen_at desc);
create index if not exists marketing_touchpoints_gclid_idx on public.marketing_touchpoints(gclid) where gclid is not null;
create index if not exists marketing_touchpoints_fbclid_idx on public.marketing_touchpoints(fbclid) where fbclid is not null;
create index if not exists marketing_conversion_events_job_idx on public.marketing_conversion_events(job_id, event_time desc);
create index if not exists marketing_conversion_events_touchpoint_idx on public.marketing_conversion_events(touchpoint_id, event_time desc);
create index if not exists marketing_ad_metrics_campaign_date_idx on public.marketing_ad_daily_metrics(campaign_external_id, metric_date desc);

alter table public.marketing_ad_accounts enable row level security;
alter table public.marketing_ad_entities enable row level security;
alter table public.marketing_ad_daily_metrics enable row level security;
alter table public.marketing_touchpoints enable row level security;
alter table public.marketing_conversion_events enable row level security;
revoke all on public.marketing_ad_accounts,public.marketing_ad_entities,public.marketing_ad_daily_metrics,public.marketing_touchpoints,public.marketing_conversion_events from public,anon,authenticated;

create or replace function private.marketing_attribution_dashboard_impl(p_days integer default 30)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  with bounds as (select current_date - greatest(1,least(coalesce(p_days,30),3650)) as start_date),
  spend as (
    select coalesce(sum(m.spend),0) spend, coalesce(sum(m.clicks),0) clicks, coalesce(sum(m.impressions),0) impressions
    from public.marketing_ad_daily_metrics m,bounds b where m.metric_date>=b.start_date
  ), conv as (
    select count(*) filter(where e.event_type='lead') leads,
           count(*) filter(where e.event_type='call') calls,
           count(*) filter(where e.event_type='booked_job') booked_jobs,
           count(*) filter(where e.event_type='job_completed') completed_jobs,
           coalesce(sum(case when e.event_type in ('payment','job_completed') then coalesce(e.value,0) else 0 end),0) revenue
    from public.marketing_conversion_events e,bounds b where e.event_time::date>=b.start_date
  ), diag as (
    select count(*) filter(where coalesce(t.gclid,t.gbraid,t.wbraid,t.fbclid) is not null) identified_touchpoints,count(*) touchpoints
    from public.marketing_touchpoints t,bounds b where t.first_seen_at::date>=b.start_date
  )
  select jsonb_build_object('spend',spend.spend,'clicks',spend.clicks,'impressions',spend.impressions,'leads',conv.leads,'calls',conv.calls,'bookedJobs',conv.booked_jobs,'completedJobs',conv.completed_jobs,'revenue',conv.revenue,'touchpoints',diag.touchpoints,'identifiedTouchpoints',diag.identified_touchpoints,'roas',case when spend.spend>0 then conv.revenue/spend.spend else null end,'costPerBookedJob',case when conv.booked_jobs>0 then spend.spend/conv.booked_jobs else null end)
  from spend,conv,diag;
$$;

create or replace function public.marketing_attribution_dashboard(p_days integer default 30)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
  if not public.has_permission_for_current_user('view_reports') and not public.has_permission_for_current_user('view_csr') then raise exception 'Permission denied'; end if;
  return private.marketing_attribution_dashboard_impl(p_days);
end$$;

create or replace function private.ingest_marketing_touchpoint_impl(
  p_session_key text,p_platform text default null,p_gclid text default null,p_gbraid text default null,p_wbraid text default null,p_fbclid text default null,
  p_utm_source text default null,p_utm_medium text default null,p_utm_campaign text default null,p_utm_term text default null,p_utm_content text default null,
  p_landing_page text default null,p_referrer text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if length(trim(coalesce(p_session_key,'')))<12 then raise exception 'Invalid session key'; end if;
  insert into public.marketing_touchpoints(session_key,platform,gclid,gbraid,wbraid,fbclid,utm_source,utm_medium,utm_campaign,utm_term,utm_content,landing_page,referrer)
  values(trim(p_session_key),nullif(trim(p_platform),''),nullif(trim(p_gclid),''),nullif(trim(p_gbraid),''),nullif(trim(p_wbraid),''),nullif(trim(p_fbclid),''),nullif(trim(p_utm_source),''),nullif(trim(p_utm_medium),''),nullif(trim(p_utm_campaign),''),nullif(trim(p_utm_term),''),nullif(trim(p_utm_content),''),left(nullif(trim(p_landing_page),''),2000),left(nullif(trim(p_referrer),''),2000)) returning id into v_id;
  return v_id;
end$$;

create or replace function public.ingest_marketing_touchpoint(
  p_session_key text,p_platform text default null,p_gclid text default null,p_gbraid text default null,p_wbraid text default null,p_fbclid text default null,
  p_utm_source text default null,p_utm_medium text default null,p_utm_campaign text default null,p_utm_term text default null,p_utm_content text default null,
  p_landing_page text default null,p_referrer text default null)
returns uuid language sql security invoker set search_path='' as $$ select private.ingest_marketing_touchpoint_impl(p_session_key,p_platform,p_gclid,p_gbraid,p_wbraid,p_fbclid,p_utm_source,p_utm_medium,p_utm_campaign,p_utm_term,p_utm_content,p_landing_page,p_referrer) $$;

revoke all on function public.marketing_attribution_dashboard(integer) from public,anon;
grant execute on function public.marketing_attribution_dashboard(integer) to authenticated;
revoke all on function private.marketing_attribution_dashboard_impl(integer) from public,anon;
grant execute on function private.marketing_attribution_dashboard_impl(integer) to authenticated;
revoke all on function public.ingest_marketing_touchpoint(text,text,text,text,text,text,text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function private.ingest_marketing_touchpoint_impl(text,text,text,text,text,text,text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.ingest_marketing_touchpoint(text,text,text,text,text,text,text,text,text,text,text,text,text) to service_role;
grant execute on function private.ingest_marketing_touchpoint_impl(text,text,text,text,text,text,text,text,text,text,text,text,text) to service_role;
grant select,insert,update on public.marketing_ad_accounts,public.marketing_ad_entities,public.marketing_ad_daily_metrics,public.marketing_touchpoints,public.marketing_conversion_events to service_role;
