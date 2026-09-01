create or replace function private.upsert_marketing_ad_account_impl(p_provider text,p_external_account_id text,p_account_name text,p_currency_code text,p_timezone text,p_status text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_provider not in ('google_ads','meta_ads') then raise exception 'Invalid provider'; end if;
 if nullif(trim(coalesce(p_external_account_id,'')),'') is null then raise exception 'Account ID required'; end if;
 insert into public.marketing_ad_accounts(platform,external_account_id,account_name,currency_code,timezone,status,last_synced_at,updated_at)
 values(p_provider,trim(p_external_account_id),nullif(trim(p_account_name),''),coalesce(nullif(trim(p_currency_code),''),'USD'),nullif(trim(p_timezone),''),coalesce(nullif(trim(p_status),''),'active'),now(),now())
 on conflict(platform,external_account_id) do update set account_name=excluded.account_name,currency_code=excluded.currency_code,timezone=excluded.timezone,status=excluded.status,last_synced_at=now(),updated_at=now()
 returning id into v_id;
 insert into public.marketing_provider_connections(provider,connection_status,external_account_id,account_name,authorized_at,last_synced_at,last_error,updated_at)
 values(p_provider,'authorized',trim(p_external_account_id),nullif(trim(p_account_name),''),now(),now(),null,now())
 on conflict(provider) do update set connection_status='authorized',external_account_id=excluded.external_account_id,account_name=excluded.account_name,authorized_at=coalesce(public.marketing_provider_connections.authorized_at,now()),last_synced_at=now(),last_error=null,updated_at=now();
 perform private.activate_marketing_provider_queue_impl(p_provider);
 return v_id;
end$$;

create or replace function public.upsert_marketing_ad_account(p_provider text,p_external_account_id text,p_account_name text default null,p_currency_code text default 'USD',p_timezone text default null,p_status text default 'active')
returns uuid language sql security definer set search_path='' as $$ select private.upsert_marketing_ad_account_impl(p_provider,p_external_account_id,p_account_name,p_currency_code,p_timezone,p_status) $$;
revoke all on function public.upsert_marketing_ad_account(text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.upsert_marketing_ad_account(text,text,text,text,text,text) to service_role;

create or replace function private.upsert_marketing_ad_entity_impl(p_ad_account_id uuid,p_entity_type text,p_external_id text,p_parent_external_id text,p_name text,p_status text,p_channel text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_entity_type not in ('campaign','group','ad','keyword') then raise exception 'Invalid entity type'; end if;
 insert into public.marketing_ad_entities(ad_account_id,entity_type,external_id,parent_external_id,name,status,channel,updated_at)
 values(p_ad_account_id,p_entity_type,trim(p_external_id),nullif(trim(p_parent_external_id),''),nullif(trim(p_name),''),nullif(trim(p_status),''),nullif(trim(p_channel),''),now())
 on conflict(ad_account_id,entity_type,external_id) do update set parent_external_id=excluded.parent_external_id,name=excluded.name,status=excluded.status,channel=excluded.channel,updated_at=now()
 returning id into v_id;return v_id;
end$$;

create or replace function public.upsert_marketing_ad_entity(p_ad_account_id uuid,p_entity_type text,p_external_id text,p_parent_external_id text default null,p_name text default null,p_status text default null,p_channel text default null)
returns uuid language sql security definer set search_path='' as $$ select private.upsert_marketing_ad_entity_impl(p_ad_account_id,p_entity_type,p_external_id,p_parent_external_id,p_name,p_status,p_channel) $$;
revoke all on function public.upsert_marketing_ad_entity(uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.upsert_marketing_ad_entity(uuid,text,text,text,text,text,text) to service_role;

create or replace function private.upsert_marketing_ad_metric_impl(p_ad_account_id uuid,p_metric_date date,p_campaign_external_id text,p_group_external_id text,p_ad_external_id text,p_impressions bigint,p_clicks bigint,p_spend numeric,p_provider_conversions numeric,p_provider_conversion_value numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_group text:=coalesce(p_group_external_id,'');v_ad text:=coalesce(p_ad_external_id,'');
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_metric_date is null or nullif(trim(coalesce(p_campaign_external_id,'')),'') is null then raise exception 'Metric date and campaign required'; end if;
 insert into public.marketing_ad_daily_metrics(ad_account_id,metric_date,campaign_external_id,group_external_id,ad_external_id,impressions,clicks,spend,provider_conversions,provider_conversion_value,synced_at)
 values(p_ad_account_id,p_metric_date,trim(p_campaign_external_id),v_group,v_ad,greatest(coalesce(p_impressions,0),0),greatest(coalesce(p_clicks,0),0),greatest(coalesce(p_spend,0),0),greatest(coalesce(p_provider_conversions,0),0),greatest(coalesce(p_provider_conversion_value,0),0),now())
 on conflict(ad_account_id,metric_date,campaign_external_id,group_external_id,ad_external_id) do update set impressions=excluded.impressions,clicks=excluded.clicks,spend=excluded.spend,provider_conversions=excluded.provider_conversions,provider_conversion_value=excluded.provider_conversion_value,synced_at=now()
 returning id into v_id;
 update public.marketing_ad_accounts set last_synced_at=now(),updated_at=now() where id=p_ad_account_id;
 return v_id;
end$$;

create or replace function public.upsert_marketing_ad_metric(p_ad_account_id uuid,p_metric_date date,p_campaign_external_id text,p_group_external_id text default '',p_ad_external_id text default '',p_impressions bigint default 0,p_clicks bigint default 0,p_spend numeric default 0,p_provider_conversions numeric default 0,p_provider_conversion_value numeric default 0)
returns uuid language sql security definer set search_path='' as $$ select private.upsert_marketing_ad_metric_impl(p_ad_account_id,p_metric_date,p_campaign_external_id,p_group_external_id,p_ad_external_id,p_impressions,p_clicks,p_spend,p_provider_conversions,p_provider_conversion_value) $$;
revoke all on function public.upsert_marketing_ad_metric(uuid,date,text,text,text,bigint,bigint,numeric,numeric,numeric) from public,anon,authenticated;
grant execute on function public.upsert_marketing_ad_metric(uuid,date,text,text,text,bigint,bigint,numeric,numeric,numeric) to service_role;

create or replace function public.set_marketing_provider_sync_error(p_provider text,p_error text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_provider not in ('google_ads','meta_ads') then raise exception 'Invalid provider'; end if;
 insert into public.marketing_provider_connections(provider,connection_status,last_error,updated_at) values(p_provider,'error',left(coalesce(p_error,'Provider sync error'),2000),now())
 on conflict(provider) do update set connection_status='error',last_error=excluded.last_error,updated_at=now();
end$$;
revoke all on function public.set_marketing_provider_sync_error(text,text) from public,anon,authenticated;
grant execute on function public.set_marketing_provider_sync_error(text,text) to service_role;