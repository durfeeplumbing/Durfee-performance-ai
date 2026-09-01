create table if not exists public.marketing_tracking_numbers (
  id uuid primary key default gen_random_uuid(),
  phone_number text not null unique,
  provider text not null default 'dialpad',
  external_number_id text,
  destination_number text,
  status text not null default 'available' check (status in ('available','active','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.marketing_tracking_assignments (
  id uuid primary key default gen_random_uuid(),
  tracking_number_id uuid not null references public.marketing_tracking_numbers(id) on delete cascade,
  touchpoint_id uuid not null references public.marketing_touchpoints(id) on delete cascade,
  session_key text not null,
  assigned_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz
);
create index if not exists marketing_tracking_assignments_number_expiry_idx on public.marketing_tracking_assignments(tracking_number_id,expires_at desc);
create index if not exists marketing_tracking_assignments_touchpoint_idx on public.marketing_tracking_assignments(touchpoint_id,assigned_at desc);
create index if not exists marketing_tracking_assignments_session_idx on public.marketing_tracking_assignments(session_key,assigned_at desc);

alter table public.marketing_tracking_numbers enable row level security;
alter table public.marketing_tracking_assignments enable row level security;
revoke all on public.marketing_tracking_numbers from public,anon,authenticated;
revoke all on public.marketing_tracking_assignments from public,anon,authenticated;
grant select,insert,update,delete on public.marketing_tracking_numbers to service_role;
grant select,insert,update,delete on public.marketing_tracking_assignments to service_role;

create or replace function private.normalize_marketing_phone(p_phone text)
returns text language sql immutable set search_path='' as $$
  select case when length(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'))>10 then right(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'),10) else regexp_replace(coalesce(p_phone,''),'[^0-9]','','g') end
$$;

create or replace function private.assign_marketing_tracking_number_impl(p_session_key text,p_ttl_minutes integer default 30)
returns table(phone_number text, assignment_id uuid, expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare v_touch uuid; v_number uuid; v_exp timestamptz;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required'; end if;
  if length(trim(coalesce(p_session_key,'')))<12 then raise exception 'Invalid session key'; end if;
  select id into v_touch from public.marketing_touchpoints where session_key=p_session_key order by last_seen_at desc limit 1;
  if v_touch is null then raise exception 'Marketing touchpoint not found'; end if;
  v_exp:=now()+make_interval(mins=>greatest(5,least(coalesce(p_ttl_minutes,30),240)));
  select n.id into v_number
  from public.marketing_tracking_numbers n
  where n.status='active'
    and not exists(select 1 from public.marketing_tracking_assignments a where a.tracking_number_id=n.id and a.expires_at>now())
  order by coalesce((select max(a2.last_used_at) from public.marketing_tracking_assignments a2 where a2.tracking_number_id=n.id),'epoch'::timestamptz),n.created_at
  limit 1 for update skip locked;
  if v_number is null then return; end if;
  return query
  with ins as (
    insert into public.marketing_tracking_assignments(tracking_number_id,touchpoint_id,session_key,expires_at)
    values(v_number,v_touch,p_session_key,v_exp)
    returning id,tracking_number_id,expires_at
  ) select n.phone_number,ins.id,ins.expires_at from ins join public.marketing_tracking_numbers n on n.id=ins.tracking_number_id;
end$$;

create or replace function public.assign_marketing_tracking_number(p_session_key text,p_ttl_minutes integer default 30)
returns table(phone_number text,assignment_id uuid,expires_at timestamptz)
language sql set search_path='' as $$ select * from private.assign_marketing_tracking_number_impl(p_session_key,p_ttl_minutes) $$;
revoke all on function public.assign_marketing_tracking_number(text,integer) from public,anon,authenticated;
grant execute on function public.assign_marketing_tracking_number(text,integer) to service_role;
revoke all on function private.assign_marketing_tracking_number_impl(text,integer) from public,anon,authenticated;
grant execute on function private.assign_marketing_tracking_number_impl(text,integer) to service_role;

create or replace function private.marketing_touchpoint_for_job(p_job_id uuid,p_event_time timestamptz default now())
returns uuid language sql stable security definer set search_path='' as $$
  select t.id
  from public.jobs j
  join public.marketing_touchpoints t on (t.job_id=j.id or (t.job_id is null and t.customer_id=j.customer_id and t.first_seen_at between j.created_at-interval '90 days' and coalesce(p_event_time,now())))
  where j.id=p_job_id
  order by case when t.job_id=j.id then 0 else 1 end,t.first_seen_at desc
  limit 1
$$;

create or replace function private.upsert_marketing_conversion(p_job_id uuid,p_invoice_id uuid,p_payment_id uuid,p_event_type text,p_event_time timestamptz,p_value numeric,p_transaction_id text)
returns void language plpgsql security definer set search_path='' as $$
declare v_touch uuid; v_customer uuid;
begin
  if p_job_id is null or p_transaction_id is null then return; end if;
  select customer_id into v_customer from public.jobs where id=p_job_id;
  if v_customer is null then return; end if;
  v_touch:=private.marketing_touchpoint_for_job(p_job_id,p_event_time);
  if v_touch is null then return; end if;
  insert into public.marketing_conversion_events(touchpoint_id,customer_id,job_id,invoice_id,payment_id,event_type,event_time,value,currency_code,transaction_id,google_upload_status,meta_upload_status)
  values(v_touch,v_customer,p_job_id,p_invoice_id,p_payment_id,p_event_type,coalesce(p_event_time,now()),greatest(coalesce(p_value,0),0),'USD',p_transaction_id,'pending','pending')
  on conflict(event_type,transaction_id) do update set touchpoint_id=excluded.touchpoint_id,customer_id=excluded.customer_id,job_id=excluded.job_id,invoice_id=excluded.invoice_id,payment_id=excluded.payment_id,event_time=excluded.event_time,value=excluded.value;
end$$;

create or replace function private.reconcile_marketing_job_impl(p_job_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare j public.jobs%rowtype; i record; p record;
begin
  select * into j from public.jobs where id=p_job_id;
  if j.id is null then return; end if;
  if j.completed_at is not null then perform private.upsert_marketing_conversion(j.id,null,null,'completed_job',j.completed_at,j.revenue,'job:'||j.id::text); end if;
  for i in select id,total,created_at from public.invoices where job_id=j.id loop
    perform private.upsert_marketing_conversion(j.id,i.id,null,'invoice',i.created_at,i.total,'invoice:'||i.id::text);
  end loop;
  for p in select id,amount,received_at from public.payments where job_id=j.id loop
    perform private.upsert_marketing_conversion(j.id,null,p.id,'payment',p.received_at,p.amount,'payment:'||p.id::text);
  end loop;
end$$;

create or replace function public.reconcile_marketing_job(p_job_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required'; end if;
  perform private.reconcile_marketing_job_impl(p_job_id);
end$$;
revoke all on function public.reconcile_marketing_job(uuid) from public,anon,authenticated;
grant execute on function public.reconcile_marketing_job(uuid) to service_role;

create or replace function private.link_marketing_call_impl(p_communication_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.customer_communications%rowtype; v_touch uuid; v_assignment uuid; v_job uuid;
begin
  select * into c from public.customer_communications where id=p_communication_id;
  if c.id is null or c.channel<>'phone' or c.direction<>'inbound' then return null; end if;
  select a.touchpoint_id,a.id into v_touch,v_assignment
  from public.marketing_tracking_assignments a
  join public.marketing_tracking_numbers n on n.id=a.tracking_number_id
  where private.normalize_marketing_phone(n.phone_number)=private.normalize_marketing_phone(c.to_address)
    and a.assigned_at<=c.occurred_at and a.expires_at>=c.occurred_at-interval '5 minutes'
  order by a.assigned_at desc limit 1;
  if v_touch is null then return null; end if;
  v_job:=coalesce(c.job_id,c.booked_job_id);
  update public.marketing_touchpoints set communication_id=c.id,customer_id=coalesce(customer_id,c.customer_id),job_id=coalesce(job_id,v_job),last_seen_at=greatest(last_seen_at,c.occurred_at) where id=v_touch;
  update public.marketing_tracking_assignments set last_used_at=c.occurred_at where id=v_assignment;
  insert into public.marketing_conversion_events(touchpoint_id,customer_id,job_id,event_type,event_time,value,currency_code,transaction_id,google_upload_status,meta_upload_status)
  values(v_touch,c.customer_id,v_job,'phone_call',c.occurred_at,0,'USD','call:'||c.id::text,'pending','pending')
  on conflict(event_type,transaction_id) do update set touchpoint_id=excluded.touchpoint_id,customer_id=excluded.customer_id,job_id=excluded.job_id,event_time=excluded.event_time;
  if v_job is not null then perform private.reconcile_marketing_job_impl(v_job); end if;
  return v_touch;
end$$;

create or replace function public.link_marketing_call(p_communication_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required'; end if;
  return private.link_marketing_call_impl(p_communication_id);
end$$;
revoke all on function public.link_marketing_call(uuid) from public,anon,authenticated;
grant execute on function public.link_marketing_call(uuid) to service_role;

create or replace function private.marketing_conversion_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='jobs' then perform private.reconcile_marketing_job_impl(new.id);
  elsif tg_table_name='invoices' then perform private.reconcile_marketing_job_impl(new.job_id);
  elsif tg_table_name='payments' then perform private.reconcile_marketing_job_impl(new.job_id);
  end if;
  return new;
end$$;

drop trigger if exists jobs_marketing_conversion_reconcile on public.jobs;
create trigger jobs_marketing_conversion_reconcile after insert or update of completed_at,revenue on public.jobs for each row execute function private.marketing_conversion_trigger();
drop trigger if exists invoices_marketing_conversion_reconcile on public.invoices;
create trigger invoices_marketing_conversion_reconcile after insert or update of total,status on public.invoices for each row execute function private.marketing_conversion_trigger();
drop trigger if exists payments_marketing_conversion_reconcile on public.payments;
create trigger payments_marketing_conversion_reconcile after insert or update of amount,received_at on public.payments for each row execute function private.marketing_conversion_trigger();

create or replace function public.marketing_attribution_diagnostics(p_days integer default 30)
returns jsonb language plpgsql stable set search_path='' as $$
declare v jsonb;
begin
  if not public.has_permission_for_current_user('view_reports') and not public.has_permission_for_current_user('view_csr') then raise exception 'Permission denied'; end if;
  select jsonb_build_object(
    'touchpoints',count(*) filter(where t.first_seen_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650)))),
    'identified',count(*) filter(where t.first_seen_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))) and coalesce(t.gclid,t.gbraid,t.wbraid,t.fbclid) is not null),
    'linkedCalls',count(*) filter(where t.first_seen_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))) and t.communication_id is not null),
    'linkedCustomers',count(*) filter(where t.first_seen_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))) and t.customer_id is not null),
    'linkedJobs',count(*) filter(where t.first_seen_at>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))) and t.job_id is not null),
    'trackingNumbers', (select count(*) from public.marketing_tracking_numbers where status='active'),
    'pendingGoogleConversions',(select count(*) from public.marketing_conversion_events where google_upload_status='pending'),
    'pendingMetaConversions',(select count(*) from public.marketing_conversion_events where meta_upload_status='pending'),
    'conversionEvents',(select count(*) from public.marketing_conversion_events where event_time>=now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),3650))))
  ) into v from public.marketing_touchpoints t;
  return v;
end$$;
revoke all on function public.marketing_attribution_diagnostics(integer) from public,anon;
grant execute on function public.marketing_attribution_diagnostics(integer) to authenticated;
