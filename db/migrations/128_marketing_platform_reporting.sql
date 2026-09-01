create or replace function public.marketing_platform_summary(p_days integer default 30)
returns table(platform text,account_name text,status text,last_synced_at timestamptz,spend numeric,impressions bigint,clicks bigint,provider_conversions numeric,provider_conversion_value numeric)
language sql stable security invoker set search_path='' as $$
  select a.platform,a.account_name,a.status,a.last_synced_at,
    coalesce(sum(m.spend),0)::numeric,
    coalesce(sum(m.impressions),0)::bigint,
    coalesce(sum(m.clicks),0)::bigint,
    coalesce(sum(m.provider_conversions),0)::numeric,
    coalesce(sum(m.provider_conversion_value),0)::numeric
  from public.marketing_ad_accounts a
  left join public.marketing_ad_daily_metrics m on m.ad_account_id=a.id and m.metric_date>=current_date-greatest(1,least(coalesce(p_days,30),3650))
  where public.has_permission_for_current_user('view_reports') or public.has_permission_for_current_user('view_csr')
  group by a.id,a.platform,a.account_name,a.status,a.last_synced_at
  order by a.platform,a.account_name;
$$;
revoke all on function public.marketing_platform_summary(integer) from public,anon;
grant execute on function public.marketing_platform_summary(integer) to authenticated;

create or replace function public.marketing_campaign_performance(p_days integer default 30,p_limit integer default 50)
returns table(platform text,campaign_external_id text,campaign_name text,spend numeric,impressions bigint,clicks bigint,provider_conversions numeric,provider_conversion_value numeric)
language sql stable security invoker set search_path='' as $$
  select a.platform,m.campaign_external_id,max(e.name) as campaign_name,
    coalesce(sum(m.spend),0)::numeric,coalesce(sum(m.impressions),0)::bigint,coalesce(sum(m.clicks),0)::bigint,
    coalesce(sum(m.provider_conversions),0)::numeric,coalesce(sum(m.provider_conversion_value),0)::numeric
  from public.marketing_ad_daily_metrics m
  join public.marketing_ad_accounts a on a.id=m.ad_account_id
  left join public.marketing_ad_entities e on e.ad_account_id=a.id and e.entity_type='campaign' and e.external_id=m.campaign_external_id
  where (public.has_permission_for_current_user('view_reports') or public.has_permission_for_current_user('view_csr'))
    and m.metric_date>=current_date-greatest(1,least(coalesce(p_days,30),3650))
  group by a.platform,m.campaign_external_id
  order by sum(m.spend) desc
  limit greatest(1,least(coalesce(p_limit,50),200));
$$;
revoke all on function public.marketing_campaign_performance(integer,integer) from public,anon;
grant execute on function public.marketing_campaign_performance(integer,integer) to authenticated;
