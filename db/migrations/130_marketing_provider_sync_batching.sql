create or replace function private.claim_marketing_conversion_batch_impl(p_provider text,p_limit integer default 100)
returns table(queue_id uuid,conversion_event_id uuid,event_type text,event_time timestamptz,value numeric,currency_code text,transaction_id text,gclid text,gbraid text,wbraid text,fbclid text)
language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
  if p_provider not in ('google_ads','meta_ads') then raise exception 'Invalid provider'; end if;
  return query
  with picked as (
    select q.id from public.marketing_conversion_sync_queue q
    where q.provider=p_provider and q.status in ('ready','failed') and coalesce(q.next_attempt_at,'epoch'::timestamptz)<=now()
    order by coalesce(q.next_attempt_at,q.created_at),q.created_at
    limit greatest(1,least(coalesce(p_limit,100),500))
    for update skip locked
  ), claimed as (
    update public.marketing_conversion_sync_queue q set status='processing',attempts=q.attempts+1,last_attempt_at=now(),updated_at=now()
    from picked where q.id=picked.id returning q.*
  )
  select q.id,e.id,e.event_type,e.event_time,e.value,e.currency_code,e.transaction_id,t.gclid,t.gbraid,t.wbraid,t.fbclid
  from claimed q join public.marketing_conversion_events e on e.id=q.conversion_event_id left join public.marketing_touchpoints t on t.id=e.touchpoint_id;
end$$;

create or replace function public.claim_marketing_conversion_batch(p_provider text,p_limit integer default 100)
returns table(queue_id uuid,conversion_event_id uuid,event_type text,event_time timestamptz,value numeric,currency_code text,transaction_id text,gclid text,gbraid text,wbraid text,fbclid text)
language sql security definer set search_path='' as $$ select * from private.claim_marketing_conversion_batch_impl(p_provider,p_limit) $$;
revoke all on function public.claim_marketing_conversion_batch(text,integer) from public,anon,authenticated;
grant execute on function public.claim_marketing_conversion_batch(text,integer) to service_role;

create or replace function private.finish_marketing_conversion_sync_impl(p_queue_id uuid,p_success boolean,p_provider_event_id text default null,p_error text default null,p_retry_minutes integer default 60)
returns void language plpgsql security definer set search_path='' as $$
declare q public.marketing_conversion_sync_queue%rowtype;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 select * into q from public.marketing_conversion_sync_queue where id=p_queue_id for update;
 if q.id is null then raise exception 'Queue item not found'; end if;
 update public.marketing_conversion_sync_queue set status=case when p_success then 'sent' else 'failed' end,provider_event_id=case when p_success then nullif(trim(coalesce(p_provider_event_id,'')),'') else provider_event_id end,last_error=case when p_success then null else left(coalesce(p_error,'Provider sync failed'),2000) end,next_attempt_at=case when p_success then null else now()+make_interval(mins=>greatest(15,least(coalesce(p_retry_minutes,60),1440))) end,updated_at=now() where id=q.id;
 if q.provider='google_ads' then update public.marketing_conversion_events set google_upload_status=case when p_success then 'sent' else 'failed' end,provider_error=case when p_success then null else left(coalesce(p_error,'Provider sync failed'),2000) end where id=q.conversion_event_id;
 else update public.marketing_conversion_events set meta_upload_status=case when p_success then 'sent' else 'failed' end,provider_error=case when p_success then null else left(coalesce(p_error,'Provider sync failed'),2000) end where id=q.conversion_event_id;
 end if;
end$$;

create or replace function public.finish_marketing_conversion_sync(p_queue_id uuid,p_success boolean,p_provider_event_id text default null,p_error text default null,p_retry_minutes integer default 60)
returns void language sql security definer set search_path='' as $$ select private.finish_marketing_conversion_sync_impl(p_queue_id,p_success,p_provider_event_id,p_error,p_retry_minutes) $$;
revoke all on function public.finish_marketing_conversion_sync(uuid,boolean,text,text,integer) from public,anon,authenticated;
grant execute on function public.finish_marketing_conversion_sync(uuid,boolean,text,text,integer) to service_role;

create or replace function private.activate_marketing_provider_queue_impl(p_provider text)
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_provider not in ('google_ads','meta_ads') then raise exception 'Invalid provider'; end if;
 update public.marketing_conversion_sync_queue q set status='ready',updated_at=now()
 where q.provider=p_provider and q.status='waiting_authorization' and exists(
  select 1 from public.marketing_conversion_events e join public.marketing_touchpoints t on t.id=e.touchpoint_id
  where e.id=q.conversion_event_id and ((p_provider='google_ads' and coalesce(t.gclid,t.gbraid,t.wbraid) is not null) or (p_provider='meta_ads' and t.fbclid is not null))
 );
 get diagnostics n=row_count; return n;
end$$;

create or replace function public.activate_marketing_provider_queue(p_provider text)
returns integer language sql security definer set search_path='' as $$ select private.activate_marketing_provider_queue_impl(p_provider) $$;
revoke all on function public.activate_marketing_provider_queue(text) from public,anon,authenticated;
grant execute on function public.activate_marketing_provider_queue(text) to service_role;
