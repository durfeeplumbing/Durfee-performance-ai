create or replace function private.link_marketing_touchpoint_impl(p_touchpoint_id uuid,p_customer_id uuid default null,p_job_id uuid default null,p_communication_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_job_id is not null and p_customer_id is not null and not exists(select 1 from public.jobs j where j.id=p_job_id and j.customer_id=p_customer_id) then raise exception 'Job does not belong to customer'; end if;
  if p_communication_id is not null and p_customer_id is not null and not exists(select 1 from public.customer_communications c where c.id=p_communication_id and c.customer_id=p_customer_id) then raise exception 'Communication does not belong to customer'; end if;
  update public.marketing_touchpoints set customer_id=coalesce(p_customer_id,customer_id),job_id=coalesce(p_job_id,job_id),communication_id=coalesce(p_communication_id,communication_id),last_seen_at=now() where id=p_touchpoint_id;
  if not found then raise exception 'Touchpoint not found'; end if;
end$$;

create or replace function public.link_marketing_touchpoint(p_touchpoint_id uuid,p_customer_id uuid default null,p_job_id uuid default null,p_communication_id uuid default null)
returns void language plpgsql security invoker set search_path='' as $$
begin
  if not public.has_permission_for_current_user('manage_csr') then raise exception 'Permission denied'; end if;
  perform private.link_marketing_touchpoint_impl(p_touchpoint_id,p_customer_id,p_job_id,p_communication_id);
end$$;

create or replace function private.record_marketing_conversion_impl(p_touchpoint_id uuid,p_customer_id uuid,p_job_id uuid,p_invoice_id uuid,p_payment_id uuid,p_event_type text,p_event_time timestamptz,p_value numeric,p_currency_code text,p_transaction_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_google text; v_meta text;
begin
  if p_event_type not in ('lead','call','booked_job','estimate_sold','job_completed','invoice','payment','revenue_adjustment') then raise exception 'Invalid event type'; end if;
  select case when coalesce(t.gclid,t.gbraid,t.wbraid) is not null then 'ready' else 'not_ready' end,
         case when t.fbclid is not null then 'ready' else 'not_ready' end
    into v_google,v_meta from public.marketing_touchpoints t where t.id=p_touchpoint_id;
  insert into public.marketing_conversion_events(touchpoint_id,customer_id,job_id,invoice_id,payment_id,event_type,event_time,value,currency_code,transaction_id,google_upload_status,meta_upload_status)
  values(p_touchpoint_id,p_customer_id,p_job_id,p_invoice_id,p_payment_id,p_event_type,coalesce(p_event_time,now()),p_value,coalesce(nullif(p_currency_code,''),'USD'),nullif(p_transaction_id,''),coalesce(v_google,'not_ready'),coalesce(v_meta,'not_ready'))
  on conflict(event_type,transaction_id) do update set value=excluded.value,event_time=excluded.event_time,touchpoint_id=coalesce(excluded.touchpoint_id,public.marketing_conversion_events.touchpoint_id),customer_id=coalesce(excluded.customer_id,public.marketing_conversion_events.customer_id),job_id=coalesce(excluded.job_id,public.marketing_conversion_events.job_id),invoice_id=coalesce(excluded.invoice_id,public.marketing_conversion_events.invoice_id),payment_id=coalesce(excluded.payment_id,public.marketing_conversion_events.payment_id)
  returning id into v_id;
  return v_id;
end$$;

create or replace function public.record_marketing_conversion(p_touchpoint_id uuid default null,p_customer_id uuid default null,p_job_id uuid default null,p_invoice_id uuid default null,p_payment_id uuid default null,p_event_type text default 'lead',p_event_time timestamptz default now(),p_value numeric default null,p_currency_code text default 'USD',p_transaction_id text default null)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
  if not public.has_permission_for_current_user('manage_csr') then raise exception 'Permission denied'; end if;
  return private.record_marketing_conversion_impl(p_touchpoint_id,p_customer_id,p_job_id,p_invoice_id,p_payment_id,p_event_type,p_event_time,p_value,p_currency_code,p_transaction_id);
end$$;

create or replace function public.marketing_touchpoint_recent(p_days integer default 30,p_limit integer default 100)
returns table(id uuid,session_key text,platform text,gclid text,gbraid text,wbraid text,fbclid text,utm_source text,utm_medium text,utm_campaign text,utm_term text,landing_page text,referrer text,customer_id uuid,job_id uuid,communication_id uuid,first_seen_at timestamptz,last_seen_at timestamptz)
language sql stable security invoker set search_path='' as $$
  select t.id,t.session_key,t.platform,t.gclid,t.gbraid,t.wbraid,t.fbclid,t.utm_source,t.utm_medium,t.utm_campaign,t.utm_term,t.landing_page,t.referrer,t.customer_id,t.job_id,t.communication_id,t.first_seen_at,t.last_seen_at
  from public.marketing_touchpoints t
  where (public.has_permission_for_current_user('view_reports') or public.has_permission_for_current_user('view_csr')) and t.first_seen_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650)))
  order by t.first_seen_at desc limit greatest(1,least(coalesce(p_limit,100),500));
$$;

revoke all on function public.link_marketing_touchpoint(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function public.link_marketing_touchpoint(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function private.link_marketing_touchpoint_impl(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function private.link_marketing_touchpoint_impl(uuid,uuid,uuid,uuid) to authenticated;
revoke all on function public.record_marketing_conversion(uuid,uuid,uuid,uuid,uuid,text,timestamptz,numeric,text,text) from public,anon;
grant execute on function public.record_marketing_conversion(uuid,uuid,uuid,uuid,uuid,text,timestamptz,numeric,text,text) to authenticated;
revoke all on function private.record_marketing_conversion_impl(uuid,uuid,uuid,uuid,uuid,text,timestamptz,numeric,text,text) from public,anon;
grant execute on function private.record_marketing_conversion_impl(uuid,uuid,uuid,uuid,uuid,text,timestamptz,numeric,text,text) to authenticated;
revoke all on function public.marketing_touchpoint_recent(integer,integer) from public,anon;
grant execute on function public.marketing_touchpoint_recent(integer,integer) to authenticated;
