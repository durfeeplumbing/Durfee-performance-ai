create or replace function private.claim_marketing_conversion_batch_v2_impl(p_provider text,p_limit integer default 100)
returns table(queue_id uuid,conversion_event_id uuid,event_type text,event_time timestamptz,value numeric,currency_code text,transaction_id text,gclid text,gbraid text,wbraid text,fbclid text,email text,phone text,external_campaign_id text,external_group_id text,external_ad_id text)
language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if p_provider not in ('google_ads','meta_ads') then raise exception 'Invalid provider'; end if;
 return query
 with picked as (
  select q.id from public.marketing_conversion_sync_queue q
  where q.provider=p_provider and q.status in ('ready','failed') and coalesce(q.next_attempt_at,'epoch'::timestamptz)<=now()
  order by coalesce(q.next_attempt_at,q.created_at),q.created_at
  limit greatest(1,least(coalesce(p_limit,100),500)) for update skip locked
 ), claimed as (
  update public.marketing_conversion_sync_queue q set status='processing',attempts=q.attempts+1,last_attempt_at=now(),updated_at=now()
  from picked where q.id=picked.id returning q.*
 )
 select q.id,e.id,e.event_type,e.event_time,e.value,e.currency_code,e.transaction_id,t.gclid,t.gbraid,t.wbraid,t.fbclid,c.email,c.phone,t.external_campaign_id,t.external_group_id,t.external_ad_id
 from claimed q join public.marketing_conversion_events e on e.id=q.conversion_event_id
 left join public.marketing_touchpoints t on t.id=e.touchpoint_id left join public.customers c on c.id=e.customer_id;
end$$;

create or replace function public.claim_marketing_conversion_batch_v2(p_provider text,p_limit integer default 100)
returns table(queue_id uuid,conversion_event_id uuid,event_type text,event_time timestamptz,value numeric,currency_code text,transaction_id text,gclid text,gbraid text,wbraid text,fbclid text,email text,phone text,external_campaign_id text,external_group_id text,external_ad_id text)
language sql security definer set search_path='' as $$ select * from private.claim_marketing_conversion_batch_v2_impl(p_provider,p_limit) $$;
revoke all on function public.claim_marketing_conversion_batch_v2(text,integer) from public,anon,authenticated;
grant execute on function public.claim_marketing_conversion_batch_v2(text,integer) to service_role;