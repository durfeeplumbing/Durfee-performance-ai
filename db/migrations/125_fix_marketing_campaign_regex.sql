create or replace function private.servicetitan_campaign_summary_impl(p_days integer default 90)
returns table(campaign_id text,jobs bigint,completed_jobs bigint,total_revenue numeric,last_job_at timestamptz)
language sql stable security definer set search_path=''
as $$
  select nullif(r.payload->>'campaignId','') as campaign_id,
    count(*)::bigint,
    count(*) filter (where coalesce(r.payload->>'completedOn','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T')::bigint,
    coalesce(sum(case when coalesce(r.payload->>'total','') ~ '^-?[0-9]+([.][0-9]+)?$' then (r.payload->>'total')::numeric else 0 end),0),
    max(case when coalesce(r.payload->>'createdOn','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' then (r.payload->>'createdOn')::timestamptz end)
  from public.service_titan_records r
  where r.resource='jobs'
    and nullif(r.payload->>'campaignId','') is not null
    and coalesce(r.payload->>'createdOn','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
    and (r.payload->>'createdOn')::timestamptz >= now() - make_interval(days=>greatest(1,least(coalesce(p_days,90),3650)))
  group by nullif(r.payload->>'campaignId','')
  order by count(*) desc
  limit 100;
$$;
