alter table public.marketing_touchpoints
  add column if not exists external_campaign_id text,
  add column if not exists external_group_id text,
  add column if not exists external_ad_id text,
  add column if not exists device text,
  add column if not exists network text,
  add column if not exists match_type text;

create index if not exists marketing_touchpoints_campaign_idx on public.marketing_touchpoints(platform,external_campaign_id,first_seen_at desc) where external_campaign_id is not null;
create index if not exists marketing_touchpoints_customer_recent_idx on public.marketing_touchpoints(customer_id,first_seen_at desc) where customer_id is not null;

create table if not exists public.marketing_lead_submissions (
  id uuid primary key default gen_random_uuid(),
  session_key text not null,
  touchpoint_id uuid references public.marketing_touchpoints(id) on delete set null,
  form_name text,
  lead_name text,
  phone text,
  email text,
  service_request text,
  landing_page text,
  normalized_phone text generated always as (case when length(regexp_replace(coalesce(phone,''),'[^0-9]','','g'))>10 then right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),10) else regexp_replace(coalesce(phone,''),'[^0-9]','','g') end) stored,
  normalized_email text generated always as (lower(trim(coalesce(email,'')))) stored,
  status text not null default 'new' check (status in ('new','matched','converted','dismissed')),
  customer_id uuid references public.customers(id) on delete set null,
  job_id uuid references public.jobs(id) on delete set null,
  submitted_at timestamptz not null default now(),
  matched_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.marketing_lead_submissions enable row level security;
revoke all on public.marketing_lead_submissions from anon,authenticated;
grant select,insert,update,delete on public.marketing_lead_submissions to service_role;
create index if not exists marketing_lead_submissions_session_idx on public.marketing_lead_submissions(session_key,submitted_at desc);
create index if not exists marketing_lead_submissions_phone_idx on public.marketing_lead_submissions(normalized_phone,submitted_at desc) where normalized_phone<>'';
create index if not exists marketing_lead_submissions_email_idx on public.marketing_lead_submissions(normalized_email,submitted_at desc) where normalized_email<>'';
create index if not exists marketing_lead_submissions_customer_idx on public.marketing_lead_submissions(customer_id,submitted_at desc) where customer_id is not null;
create index if not exists marketing_lead_submissions_job_idx on public.marketing_lead_submissions(job_id) where job_id is not null;
create index if not exists marketing_lead_submissions_touchpoint_idx on public.marketing_lead_submissions(touchpoint_id) where touchpoint_id is not null;

create table if not exists public.marketing_provider_connections (
  provider text primary key check (provider in ('google_ads','meta_ads')),
  connection_status text not null default 'disconnected' check (connection_status in ('disconnected','authorization_required','authorized','syncing','error')),
  external_account_id text,
  account_name text,
  granted_scopes text[] not null default '{}',
  authorized_at timestamptz,
  last_synced_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);
alter table public.marketing_provider_connections enable row level security;
revoke all on public.marketing_provider_connections from anon,authenticated;
grant select,insert,update,delete on public.marketing_provider_connections to service_role;
insert into public.marketing_provider_connections(provider,connection_status) values
 ('google_ads','authorization_required'),('meta_ads','authorization_required')
on conflict(provider) do nothing;

create or replace function private.ingest_marketing_touchpoint_v2_impl(
 p_session_key text,p_platform text default null,p_gclid text default null,p_gbraid text default null,p_wbraid text default null,p_fbclid text default null,
 p_utm_source text default null,p_utm_medium text default null,p_utm_campaign text default null,p_utm_term text default null,p_utm_content text default null,
 p_landing_page text default null,p_referrer text default null,p_external_campaign_id text default null,p_external_group_id text default null,p_external_ad_id text default null,
 p_device text default null,p_network text default null,p_match_type text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if length(trim(coalesce(p_session_key,'')))<12 then raise exception 'Invalid session key'; end if;
 select id into v_id from public.marketing_touchpoints where session_key=trim(p_session_key) order by last_seen_at desc limit 1;
 if v_id is null then
  insert into public.marketing_touchpoints(session_key,platform,gclid,gbraid,wbraid,fbclid,utm_source,utm_medium,utm_campaign,utm_term,utm_content,landing_page,referrer,external_campaign_id,external_group_id,external_ad_id,device,network,match_type)
  values(trim(p_session_key),nullif(trim(p_platform),''),nullif(trim(p_gclid),''),nullif(trim(p_gbraid),''),nullif(trim(p_wbraid),''),nullif(trim(p_fbclid),''),nullif(trim(p_utm_source),''),nullif(trim(p_utm_medium),''),nullif(trim(p_utm_campaign),''),nullif(trim(p_utm_term),''),nullif(trim(p_utm_content),''),left(nullif(trim(p_landing_page),''),2000),left(nullif(trim(p_referrer),''),2000),nullif(trim(p_external_campaign_id),''),nullif(trim(p_external_group_id),''),nullif(trim(p_external_ad_id),''),nullif(trim(p_device),''),nullif(trim(p_network),''),nullif(trim(p_match_type),'')) returning id into v_id;
 else
  update public.marketing_touchpoints set
   platform=coalesce(nullif(trim(p_platform),''),platform),gclid=coalesce(nullif(trim(p_gclid),''),gclid),gbraid=coalesce(nullif(trim(p_gbraid),''),gbraid),wbraid=coalesce(nullif(trim(p_wbraid),''),wbraid),fbclid=coalesce(nullif(trim(p_fbclid),''),fbclid),
   utm_source=coalesce(nullif(trim(p_utm_source),''),utm_source),utm_medium=coalesce(nullif(trim(p_utm_medium),''),utm_medium),utm_campaign=coalesce(nullif(trim(p_utm_campaign),''),utm_campaign),utm_term=coalesce(nullif(trim(p_utm_term),''),utm_term),utm_content=coalesce(nullif(trim(p_utm_content),''),utm_content),
   landing_page=coalesce(left(nullif(trim(p_landing_page),''),2000),landing_page),referrer=coalesce(left(nullif(trim(p_referrer),''),2000),referrer),external_campaign_id=coalesce(nullif(trim(p_external_campaign_id),''),external_campaign_id),external_group_id=coalesce(nullif(trim(p_external_group_id),''),external_group_id),external_ad_id=coalesce(nullif(trim(p_external_ad_id),''),external_ad_id),device=coalesce(nullif(trim(p_device),''),device),network=coalesce(nullif(trim(p_network),''),network),match_type=coalesce(nullif(trim(p_match_type),''),match_type),last_seen_at=now()
  where id=v_id;
 end if;
 return v_id;
end$$;

create or replace function public.ingest_marketing_touchpoint_v2(
 p_session_key text,p_platform text default null,p_gclid text default null,p_gbraid text default null,p_wbraid text default null,p_fbclid text default null,
 p_utm_source text default null,p_utm_medium text default null,p_utm_campaign text default null,p_utm_term text default null,p_utm_content text default null,
 p_landing_page text default null,p_referrer text default null,p_external_campaign_id text default null,p_external_group_id text default null,p_external_ad_id text default null,
 p_device text default null,p_network text default null,p_match_type text default null)
returns uuid language sql security definer set search_path='' as $$
 select private.ingest_marketing_touchpoint_v2_impl(p_session_key,p_platform,p_gclid,p_gbraid,p_wbraid,p_fbclid,p_utm_source,p_utm_medium,p_utm_campaign,p_utm_term,p_utm_content,p_landing_page,p_referrer,p_external_campaign_id,p_external_group_id,p_external_ad_id,p_device,p_network,p_match_type)
$$;
revoke all on function public.ingest_marketing_touchpoint_v2(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.ingest_marketing_touchpoint_v2(text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text) to service_role;

create or replace function private.ingest_marketing_lead_impl(p_session_key text,p_form_name text,p_name text,p_phone text,p_email text,p_service_request text,p_landing_page text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_touch uuid;v_lead uuid;v_customer uuid;v_event uuid;v_phone text;v_email text;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if length(trim(coalesce(p_session_key,'')))<12 then raise exception 'Invalid session key'; end if;
 if nullif(trim(coalesce(p_phone,'')),'') is null and nullif(trim(coalesce(p_email,'')),'') is null then raise exception 'Phone or email required'; end if;
 select id into v_touch from public.marketing_touchpoints where session_key=trim(p_session_key) order by last_seen_at desc limit 1;
 if v_touch is null then raise exception 'Marketing touchpoint not found'; end if;
 v_phone:=case when length(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'))>10 then right(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'),10) else regexp_replace(coalesce(p_phone,''),'[^0-9]','','g') end;
 v_email:=lower(trim(coalesce(p_email,'')));
 select c.id into v_customer from public.customers c
 where (v_phone<>'' and private.normalize_marketing_phone(c.phone)=v_phone) or (v_email<>'' and lower(trim(coalesce(c.email,'')))=v_email)
 order by case when v_phone<>'' and private.normalize_marketing_phone(c.phone)=v_phone and v_email<>'' and lower(trim(coalesce(c.email,'')))=v_email then 0 else 1 end,c.created_at desc limit 1;
 insert into public.marketing_lead_submissions(session_key,touchpoint_id,form_name,lead_name,phone,email,service_request,landing_page,status,customer_id,matched_at)
 values(trim(p_session_key),v_touch,left(nullif(trim(p_form_name),''),200),left(nullif(trim(p_name),''),300),left(nullif(trim(p_phone),''),100),left(nullif(trim(p_email),''),320),left(nullif(trim(p_service_request),''),4000),left(nullif(trim(p_landing_page),''),2000),case when v_customer is null then 'new' else 'matched' end,v_customer,case when v_customer is null then null else now() end)
 returning id into v_lead;
 if v_customer is not null then
  perform private.link_marketing_touchpoint_impl(v_touch,v_customer,null,null);
  v_event:=private.record_marketing_conversion_impl(v_touch,v_customer,null,null,null,'lead',now(),0,'USD','website-lead:'||v_lead::text);
 end if;
 return v_lead;
end$$;

create or replace function public.ingest_marketing_lead(p_session_key text,p_form_name text default null,p_name text default null,p_phone text default null,p_email text default null,p_service_request text default null,p_landing_page text default null)
returns uuid language sql security definer set search_path='' as $$ select private.ingest_marketing_lead_impl(p_session_key,p_form_name,p_name,p_phone,p_email,p_service_request,p_landing_page) $$;
revoke all on function public.ingest_marketing_lead(text,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.ingest_marketing_lead(text,text,text,text,text,text,text) to service_role;

create or replace function private.stitch_marketing_customer_impl(p_customer_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare c public.customers%rowtype;v_phone text;v_email text;r record;n integer:=0;
begin
 select * into c from public.customers where id=p_customer_id;
 if c.id is null then return 0; end if;
 v_phone:=private.normalize_marketing_phone(c.phone);v_email:=lower(trim(coalesce(c.email,'')));
 for r in
  select l.id,l.touchpoint_id from public.marketing_lead_submissions l
  where l.customer_id is null and l.status='new' and l.submitted_at>=now()-interval '90 days'
    and ((v_phone<>'' and l.normalized_phone=v_phone) or (v_email<>'' and l.normalized_email=v_email))
  order by l.submitted_at desc
 loop
  update public.marketing_lead_submissions set customer_id=c.id,status='matched',matched_at=now() where id=r.id;
  if r.touchpoint_id is not null then perform private.link_marketing_touchpoint_impl(r.touchpoint_id,c.id,null,null); end if;
  n:=n+1;
 end loop;
 return n;
end$$;

create or replace function private.marketing_customer_stitch_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.stitch_marketing_customer_impl(new.id);return new;end$$;
drop trigger if exists customers_marketing_lead_stitch on public.customers;
create trigger customers_marketing_lead_stitch after insert or update of phone,email on public.customers for each row execute function private.marketing_customer_stitch_trigger();

create or replace function public.marketing_lead_queue(p_days integer default 30,p_limit integer default 100)
returns table(id uuid,submitted_at timestamptz,status text,lead_name text,phone text,email text,service_request text,form_name text,platform text,campaign text,customer_id uuid,job_id uuid,touchpoint_id uuid)
language sql stable set search_path='' as $$
 select l.id,l.submitted_at,l.status,l.lead_name,l.phone,l.email,l.service_request,l.form_name,coalesce(t.platform,t.utm_source,'direct'),coalesce(t.utm_campaign,t.external_campaign_id,'(not set)'),l.customer_id,l.job_id,l.touchpoint_id
 from public.marketing_lead_submissions l left join public.marketing_touchpoints t on t.id=l.touchpoint_id
 where (public.has_permission_for_current_user('view_csr') or public.has_permission_for_current_user('view_reports')) and l.submitted_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650)))
 order by case l.status when 'new' then 0 when 'matched' then 1 when 'converted' then 2 else 3 end,l.submitted_at desc
 limit greatest(1,least(coalesce(p_limit,100),500));
$$;
revoke all on function public.marketing_lead_queue(integer,integer) from public,anon;
grant execute on function public.marketing_lead_queue(integer,integer) to authenticated;

create or replace function public.match_marketing_lead(p_lead_id uuid,p_customer_id uuid,p_job_id uuid default null)
returns void language plpgsql set search_path='' as $$
declare l public.marketing_lead_submissions%rowtype;
begin
 if not public.has_permission_for_current_user('manage_csr') then raise exception 'Permission denied'; end if;
 if p_job_id is not null and not exists(select 1 from public.jobs where id=p_job_id and customer_id=p_customer_id) then raise exception 'Job does not belong to customer'; end if;
 select * into l from public.marketing_lead_submissions where id=p_lead_id;
 if l.id is null then raise exception 'Lead not found'; end if;
 update public.marketing_lead_submissions set customer_id=p_customer_id,job_id=p_job_id,status=case when p_job_id is null then 'matched' else 'converted' end,matched_at=now() where id=l.id;
 if l.touchpoint_id is not null then perform private.link_marketing_touchpoint_impl(l.touchpoint_id,p_customer_id,p_job_id,null); end if;
end$$;
revoke all on function public.match_marketing_lead(uuid,uuid,uuid) from public,anon;
grant execute on function public.match_marketing_lead(uuid,uuid,uuid) to authenticated;

create or replace function public.dismiss_marketing_lead(p_lead_id uuid)
returns void language plpgsql set search_path='' as $$
begin
 if not public.has_permission_for_current_user('manage_csr') then raise exception 'Permission denied'; end if;
 update public.marketing_lead_submissions set status='dismissed' where id=p_lead_id and status in ('new','matched');
 if not found then raise exception 'Lead not found or cannot be dismissed'; end if;
end$$;
revoke all on function public.dismiss_marketing_lead(uuid) from public,anon;
grant execute on function public.dismiss_marketing_lead(uuid) to authenticated;

create or replace function public.marketing_provider_connection_summary()
returns table(provider text,connection_status text,external_account_id text,account_name text,authorized_at timestamptz,last_synced_at timestamptz,last_error text)
language sql stable set search_path='' as $$
 select c.provider,c.connection_status,c.external_account_id,c.account_name,c.authorized_at,c.last_synced_at,c.last_error
 from public.marketing_provider_connections c
 where public.has_permission_for_current_user('view_reports') or public.has_permission_for_current_user('view_csr')
 order by c.provider;
$$;
revoke all on function public.marketing_provider_connection_summary() from public,anon;
grant execute on function public.marketing_provider_connection_summary() to authenticated;

create or replace function public.marketing_campaign_revenue_performance(p_days integer default 30,p_limit integer default 100)
returns table(platform text,campaign_key text,campaign_name text,spend numeric,impressions bigint,clicks bigint,sessions bigint,calls bigint,booked_jobs bigint,completed_jobs bigint,earned_revenue numeric,collected_revenue numeric,roas numeric)
language sql stable set search_path='' as $$
with bounds as (select current_date-greatest(1,least(coalesce(p_days,30),3650)) start_date),
touch as (
 select t.id,coalesce(t.platform,t.utm_source,'direct') platform,coalesce(t.external_campaign_id,t.utm_campaign,'(not set)') campaign_key
 from public.marketing_touchpoints t,bounds b where t.first_seen_at::date>=b.start_date
),ev as (
 select e.touchpoint_id,count(*) filter(where e.event_type='call') calls,count(distinct e.job_id) filter(where e.event_type='booked_job') booked,count(distinct e.job_id) filter(where e.event_type='job_completed') completed,
 coalesce(sum(e.value) filter(where e.event_type='job_completed'),0) earned,coalesce(sum(e.value) filter(where e.event_type='payment'),0) collected
 from public.marketing_conversion_events e,bounds b where e.event_time::date>=b.start_date group by e.touchpoint_id
),attrib as (
 select t.platform,t.campaign_key,count(*) sessions,coalesce(sum(ev.calls),0) calls,coalesce(sum(ev.booked),0) booked,coalesce(sum(ev.completed),0) completed,coalesce(sum(ev.earned),0) earned,coalesce(sum(ev.collected),0) collected
 from touch t left join ev on ev.touchpoint_id=t.id group by t.platform,t.campaign_key
),media as (
 select a.platform,m.campaign_external_id campaign_key,max(e.name) campaign_name,coalesce(sum(m.spend),0) spend,coalesce(sum(m.impressions),0)::bigint impressions,coalesce(sum(m.clicks),0)::bigint clicks
 from public.marketing_ad_daily_metrics m join public.marketing_ad_accounts a on a.id=m.ad_account_id left join public.marketing_ad_entities e on e.ad_account_id=a.id and e.entity_type='campaign' and e.external_id=m.campaign_external_id,bounds b
 where m.metric_date>=b.start_date group by a.platform,m.campaign_external_id
),keys as (select platform,campaign_key from attrib union select platform,campaign_key from media)
select k.platform,k.campaign_key,coalesce(m.campaign_name,k.campaign_key),coalesce(m.spend,0)::numeric,coalesce(m.impressions,0)::bigint,coalesce(m.clicks,0)::bigint,coalesce(a.sessions,0)::bigint,coalesce(a.calls,0)::bigint,coalesce(a.booked,0)::bigint,coalesce(a.completed,0)::bigint,coalesce(a.earned,0)::numeric,coalesce(a.collected,0)::numeric,
 case when coalesce(m.spend,0)>0 then (case when coalesce(a.collected,0)>0 then a.collected else coalesce(a.earned,0) end)/m.spend else null end::numeric
from keys k left join attrib a on a.platform=k.platform and a.campaign_key=k.campaign_key left join media m on m.platform=k.platform and m.campaign_key=k.campaign_key
where public.has_permission_for_current_user('view_reports')
order by coalesce(a.collected,a.earned,0) desc,coalesce(m.spend,0) desc limit greatest(1,least(coalesce(p_limit,100),500));
$$;
revoke all on function public.marketing_campaign_revenue_performance(integer,integer) from public,anon;
grant execute on function public.marketing_campaign_revenue_performance(integer,integer) to authenticated;