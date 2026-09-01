create or replace function private.record_marketing_conversion_impl(p_touchpoint_id uuid,p_customer_id uuid,p_job_id uuid,p_invoice_id uuid,p_payment_id uuid,p_event_type text,p_event_time timestamptz,p_value numeric,p_currency_code text,p_transaction_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_google text; v_meta text;
begin
  if p_event_type not in ('lead','call','booked_job','estimate_sold','job_completed','invoice','payment','revenue_adjustment') then raise exception 'Invalid event type'; end if;
  select case when coalesce(t.gclid,t.gbraid,t.wbraid) is not null then 'pending' else 'not_ready' end,
         case when t.fbclid is not null then 'pending' else 'not_ready' end
    into v_google,v_meta from public.marketing_touchpoints t where t.id=p_touchpoint_id;
  insert into public.marketing_conversion_events(touchpoint_id,customer_id,job_id,invoice_id,payment_id,event_type,event_time,value,currency_code,transaction_id,google_upload_status,meta_upload_status)
  values(p_touchpoint_id,p_customer_id,p_job_id,p_invoice_id,p_payment_id,p_event_type,coalesce(p_event_time,now()),greatest(coalesce(p_value,0),0),coalesce(nullif(p_currency_code,''),'USD'),nullif(p_transaction_id,''),coalesce(v_google,'not_ready'),coalesce(v_meta,'not_ready'))
  on conflict(event_type,transaction_id) do update set value=excluded.value,event_time=excluded.event_time,touchpoint_id=coalesce(excluded.touchpoint_id,public.marketing_conversion_events.touchpoint_id),customer_id=coalesce(excluded.customer_id,public.marketing_conversion_events.customer_id),job_id=coalesce(excluded.job_id,public.marketing_conversion_events.job_id),invoice_id=coalesce(excluded.invoice_id,public.marketing_conversion_events.invoice_id),payment_id=coalesce(excluded.payment_id,public.marketing_conversion_events.payment_id),google_upload_status=case when public.marketing_conversion_events.google_upload_status='sent' then 'sent' else excluded.google_upload_status end,meta_upload_status=case when public.marketing_conversion_events.meta_upload_status='sent' then 'sent' else excluded.meta_upload_status end
  returning id into v_id;
  perform private.queue_marketing_conversion_sync(v_id);
  return v_id;
end$$;

create or replace function private.marketing_source_summary_impl()
returns table(source_id uuid,source_name text,category text,lead_count bigint,job_count bigint,completed_jobs bigint,booked_revenue numeric,last_attributed_at timestamptz)
language sql stable security definer set search_path='' as $$
  select s.id,s.name,s.category,
    count(distinct a.customer_id),
    count(distinct a.job_id) filter(where a.job_id is not null and a.touch_type='primary'),
    count(distinct a.job_id) filter(where a.touch_type='primary' and j.completed_at is not null),
    coalesce(sum(case when a.touch_type='primary' and a.job_id is not null then coalesce(j.revenue,0) else 0 end),0),
    max(a.attributed_at)
  from public.marketing_sources s
  left join public.lead_attributions a on a.source_id=s.id
  left join public.jobs j on j.id=a.job_id
  where s.active=true
  group by s.id,s.name,s.category
  order by coalesce(sum(case when a.touch_type='primary' then coalesce(j.revenue,0) else 0 end),0) desc,count(distinct a.customer_id) desc,s.name;
$$;

create or replace function public.marketing_touchpoint_funnel(p_days integer default 30,p_limit integer default 100)
returns table(platform text,campaign text,sessions bigint,identified_sessions bigint,calls bigint,customers bigint,jobs bigint,completed_jobs bigint,earned_revenue numeric,collected_revenue numeric)
language sql stable set search_path='' as $$
with bounds as (select now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))) since),
base as (
 select t.id,coalesce(t.platform,t.utm_source,'direct') platform,coalesce(t.utm_campaign,'(not set)') campaign,t.customer_id,t.job_id,t.communication_id,
        (coalesce(t.gclid,t.gbraid,t.wbraid,t.fbclid) is not null) identified
 from public.marketing_touchpoints t,bounds b where t.first_seen_at>=b.since
), events as (
 select e.touchpoint_id,
   bool_or(e.event_type='job_completed') completed,
   coalesce(sum(e.value) filter(where e.event_type='job_completed'),0) earned,
   coalesce(sum(e.value) filter(where e.event_type='payment'),0) collected
 from public.marketing_conversion_events e,bounds b where e.event_time>=b.since group by e.touchpoint_id
)
select b.platform,b.campaign,count(*)::bigint,count(*) filter(where b.identified)::bigint,count(*) filter(where b.communication_id is not null)::bigint,count(*) filter(where b.customer_id is not null)::bigint,count(*) filter(where b.job_id is not null)::bigint,count(*) filter(where coalesce(e.completed,false))::bigint,coalesce(sum(e.earned),0)::numeric,coalesce(sum(e.collected),0)::numeric
from base b left join events e on e.touchpoint_id=b.id
where public.has_permission_for_current_user('view_reports')
group by b.platform,b.campaign order by coalesce(sum(e.collected),sum(e.earned),0) desc,count(*) desc
limit greatest(1,least(coalesce(p_limit,100),500));
$$;
revoke all on function public.marketing_touchpoint_funnel(integer,integer) from public,anon;
grant execute on function public.marketing_touchpoint_funnel(integer,integer) to authenticated;