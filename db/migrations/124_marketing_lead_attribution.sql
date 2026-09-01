create table if not exists public.marketing_sources (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  category text not null default 'other' check (category in ('paid_search','organic_search','referral','direct','social','home_services','email','offline','other')),
  active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.lead_attributions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete cascade,
  source_id uuid not null references public.marketing_sources(id) on delete restrict,
  source_detail text,
  external_campaign_id text,
  touch_type text not null default 'primary' check (touch_type in ('first','primary','assist')),
  attributed_at timestamptz not null default now(),
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists lead_attributions_customer_idx on public.lead_attributions(customer_id,attributed_at desc);
create index if not exists lead_attributions_job_idx on public.lead_attributions(job_id) where job_id is not null;
create index if not exists lead_attributions_source_idx on public.lead_attributions(source_id,attributed_at desc);
create index if not exists lead_attributions_created_by_idx on public.lead_attributions(created_by) where created_by is not null;
create index if not exists marketing_sources_created_by_idx on public.marketing_sources(created_by) where created_by is not null;

alter table public.marketing_sources enable row level security;
alter table public.lead_attributions enable row level security;
revoke all on table public.marketing_sources from public,anon,authenticated;
revoke all on table public.lead_attributions from public,anon,authenticated;

create or replace function private.marketing_source_summary_impl()
returns table(source_id uuid,source_name text,category text,lead_count bigint,job_count bigint,completed_jobs bigint,booked_revenue numeric,last_attributed_at timestamptz)
language sql stable security definer set search_path=''
as $$
  select s.id,s.name,s.category,
    count(distinct a.customer_id),
    count(distinct a.job_id) filter (where a.job_id is not null),
    count(distinct a.job_id) filter (where j.completed_at is not null),
    coalesce(sum(case when a.job_id is not null then coalesce(j.revenue,0) else 0 end),0),
    max(a.attributed_at)
  from public.marketing_sources s
  left join public.lead_attributions a on a.source_id=s.id
  left join public.jobs j on j.id=a.job_id
  where s.active=true
  group by s.id,s.name,s.category
  order by count(distinct a.job_id) desc,count(distinct a.customer_id) desc,s.name;
$$;

create or replace function private.servicetitan_campaign_summary_impl(p_days integer default 90)
returns table(campaign_id text,jobs bigint,completed_jobs bigint,total_revenue numeric,last_job_at timestamptz)
language sql stable security definer set search_path=''
as $$
  select nullif(r.payload->>'campaignId','') as campaign_id,
    count(*)::bigint,
    count(*) filter (where coalesce(r.payload->>'completedOn','') ~ '^\\d{4}-\\d{2}-\\d{2}T')::bigint,
    coalesce(sum(case when coalesce(r.payload->>'total','') ~ '^-?[0-9]+(\\.[0-9]+)?$' then (r.payload->>'total')::numeric else 0 end),0),
    max(case when coalesce(r.payload->>'createdOn','') ~ '^\\d{4}-\\d{2}-\\d{2}T' then (r.payload->>'createdOn')::timestamptz end)
  from public.service_titan_records r
  where r.resource='jobs'
    and nullif(r.payload->>'campaignId','') is not null
    and coalesce(r.payload->>'createdOn','') ~ '^\\d{4}-\\d{2}-\\d{2}T'
    and (r.payload->>'createdOn')::timestamptz >= now() - make_interval(days=>greatest(1,least(coalesce(p_days,90),3650)))
  group by nullif(r.payload->>'campaignId','')
  order by count(*) desc
  limit 100;
$$;

create or replace function private.create_marketing_source_impl(p_name text,p_category text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor uuid;v_id uuid;v_name text;v_category text;
begin
  if not private.has_permission('manage_csr') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  v_name:=nullif(trim(coalesce(p_name,'')),'');
  v_category:=coalesce(nullif(trim(coalesce(p_category,'')),''),'other');
  if v_name is null then raise exception 'Source name required'; end if;
  if v_category not in ('paid_search','organic_search','referral','direct','social','home_services','email','offline','other') then raise exception 'Invalid source category'; end if;
  insert into public.marketing_sources(name,category,created_by) values(v_name,v_category,v_actor)
  on conflict(name) do update set category=excluded.category,active=true
  returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'marketing_source_saved','marketing_source',v_id::text,jsonb_build_object('name',v_name,'category',v_category));
  return v_id;
end;
$$;

create or replace function private.set_lead_attribution_impl(p_customer_id uuid,p_job_id uuid,p_source_id uuid,p_source_detail text,p_external_campaign_id text,p_touch_type text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor uuid;v_id uuid;v_touch text;
begin
  if not private.has_permission('manage_csr') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_customer_id is null or p_source_id is null then raise exception 'Customer and source required'; end if;
  if not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer not found'; end if;
  if p_job_id is not null and not exists(select 1 from public.jobs where id=p_job_id and customer_id=p_customer_id) then raise exception 'Job does not belong to customer'; end if;
  if not exists(select 1 from public.marketing_sources where id=p_source_id and active=true) then raise exception 'Marketing source unavailable'; end if;
  v_touch:=coalesce(nullif(trim(coalesce(p_touch_type,'')),''),'primary');
  if v_touch not in ('first','primary','assist') then raise exception 'Invalid touch type'; end if;
  insert into public.lead_attributions(customer_id,job_id,source_id,source_detail,external_campaign_id,touch_type,created_by)
  values(p_customer_id,p_job_id,p_source_id,nullif(trim(coalesce(p_source_detail,'')),''),nullif(trim(coalesce(p_external_campaign_id,'')),''),v_touch,v_actor)
  returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'lead_attribution_saved','lead_attribution',v_id::text,jsonb_build_object('customer_id',p_customer_id,'job_id',p_job_id,'source_id',p_source_id,'touch_type',v_touch));
  return v_id;
end;
$$;

create or replace function public.marketing_source_summary()
returns table(source_id uuid,source_name text,category text,lead_count bigint,job_count bigint,completed_jobs bigint,booked_revenue numeric,last_attributed_at timestamptz)
language plpgsql security invoker set search_path=''
as $$ begin if not public.has_permission_for_current_user('view_customers') then raise exception 'Permission denied'; end if; return query select * from private.marketing_source_summary_impl(); end $$;

create or replace function public.servicetitan_campaign_summary(p_days integer default 90)
returns table(campaign_id text,jobs bigint,completed_jobs bigint,total_revenue numeric,last_job_at timestamptz)
language plpgsql security invoker set search_path=''
as $$ begin if not public.has_permission_for_current_user('view_customers') then raise exception 'Permission denied'; end if; return query select * from private.servicetitan_campaign_summary_impl(p_days); end $$;

create or replace function public.create_marketing_source(p_name text,p_category text)
returns uuid language plpgsql security invoker set search_path=''
as $$ begin if not public.has_permission_for_current_user('manage_csr') then raise exception 'Permission denied'; end if; return private.create_marketing_source_impl(p_name,p_category); end $$;

create or replace function public.set_lead_attribution(p_customer_id uuid,p_job_id uuid,p_source_id uuid,p_source_detail text default null,p_external_campaign_id text default null,p_touch_type text default 'primary')
returns uuid language plpgsql security invoker set search_path=''
as $$ begin if not public.has_permission_for_current_user('manage_csr') then raise exception 'Permission denied'; end if; return private.set_lead_attribution_impl(p_customer_id,p_job_id,p_source_id,p_source_detail,p_external_campaign_id,p_touch_type); end $$;

revoke all on function private.marketing_source_summary_impl() from public,anon;
revoke all on function private.servicetitan_campaign_summary_impl(integer) from public,anon;
revoke all on function private.create_marketing_source_impl(text,text) from public,anon;
revoke all on function private.set_lead_attribution_impl(uuid,uuid,uuid,text,text,text) from public,anon;
grant execute on function private.marketing_source_summary_impl() to authenticated;
grant execute on function private.servicetitan_campaign_summary_impl(integer) to authenticated;
grant execute on function private.create_marketing_source_impl(text,text) to authenticated;
grant execute on function private.set_lead_attribution_impl(uuid,uuid,uuid,text,text,text) to authenticated;

revoke all on function public.marketing_source_summary() from public,anon;
revoke all on function public.servicetitan_campaign_summary(integer) from public,anon;
revoke all on function public.create_marketing_source(text,text) from public,anon;
revoke all on function public.set_lead_attribution(uuid,uuid,uuid,text,text,text) from public,anon;
grant execute on function public.marketing_source_summary() to authenticated;
grant execute on function public.servicetitan_campaign_summary(integer) to authenticated;
grant execute on function public.create_marketing_source(text,text) to authenticated;
grant execute on function public.set_lead_attribution(uuid,uuid,uuid,text,text,text) to authenticated;