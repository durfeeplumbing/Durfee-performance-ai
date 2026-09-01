create table if not exists public.customer_review_requests (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null unique references public.jobs(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  technician_id uuid references public.users(id),
  status text not null default 'eligible' check (status in ('eligible','requested','received','declined','suppressed')),
  channel text check (channel is null or channel in ('sms','email','phone','manual')),
  requested_by uuid references public.users(id),
  requested_at timestamptz,
  rating smallint check (rating is null or rating between 1 and 5),
  feedback text,
  review_platform text,
  external_review_url text,
  review_received_at timestamptz,
  manager_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists customer_review_requests_customer_id_idx on public.customer_review_requests(customer_id);
create index if not exists customer_review_requests_technician_id_idx on public.customer_review_requests(technician_id);
create index if not exists customer_review_requests_requested_by_idx on public.customer_review_requests(requested_by);
create index if not exists customer_review_requests_status_idx on public.customer_review_requests(status);
create index if not exists customer_review_requests_requested_at_idx on public.customer_review_requests(requested_at desc);

alter table public.customer_review_requests enable row level security;
revoke all on table public.customer_review_requests from public, anon, authenticated;
grant usage on schema private to authenticated;

create or replace function private.review_management_queue_impl(p_days integer default 30)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_days integer; v_result jsonb;
begin
  if not public.has_permission_for_current_user('view_csr') and not public.has_permission_for_current_user('manage_csr') and not public.has_permission_for_current_user('manage_customers') then raise exception 'Review management access required'; end if;
  v_days:=greatest(1,least(coalesce(p_days,30),365));
  select coalesce(jsonb_agg(row_data order by completed_at desc),'[]'::jsonb) into v_result from (
    select jsonb_build_object(
      'jobId',j.id,'customerId',j.customer_id,'customerName',c.name,'customerPhone',c.phone,'customerEmail',c.email,'serviceAddress',c.service_address,
      'technicianId',j.technician_id,'technicianName',u.name,'serviceType',j.service_type,'serviceSummary',j.service_summary,'completedAt',j.completed_at,
      'status',coalesce(r.status,'eligible'),'channel',r.channel,'requestedAt',r.requested_at,'rating',r.rating,'feedback',r.feedback,'reviewPlatform',r.review_platform,
      'externalReviewUrl',r.external_review_url,'reviewReceivedAt',r.review_received_at,'managerNote',r.manager_note,
      'pendingCallbackReview',exists(select 1 from public.job_callbacks cb where cb.original_job_id=j.id and cb.preventability='pending'),
      'preventableCallback',exists(select 1 from public.job_callbacks cb where cb.original_job_id=j.id and cb.preventability in ('preventable','mixed')),
      'reviewRecommended',(r.id is null and j.completed_at>=now()-interval '14 days' and not exists(select 1 from public.job_callbacks cb where cb.original_job_id=j.id and cb.preventability in ('pending','preventable','mixed')))
    ) row_data,j.completed_at
    from public.jobs j join public.customers c on c.id=j.customer_id left join public.users u on u.id=j.technician_id left join public.customer_review_requests r on r.job_id=j.id
    where j.completed_at>=now()-make_interval(days=>v_days) and j.status in ('completed','closed')
  ) q;
  return v_result;
end;$$;

create or replace function private.record_customer_review_request_impl(p_job_id uuid,p_channel text,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job public.jobs%rowtype; v_id uuid;
begin
  if not public.has_permission_for_current_user('manage_csr') and not public.has_permission_for_current_user('manage_customers') then raise exception 'Review request permission required'; end if;
  if p_channel not in ('sms','email','phone','manual') then raise exception 'Invalid review request channel'; end if;
  select * into v_job from public.jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;
  if v_job.status not in ('completed','closed') or v_job.completed_at is null then raise exception 'Only completed jobs can receive review requests'; end if;
  if exists(select 1 from public.job_callbacks cb where cb.original_job_id=p_job_id and cb.preventability in ('pending','preventable','mixed')) then raise exception 'Resolve callback quality review before requesting a public review'; end if;
  insert into public.customer_review_requests(job_id,customer_id,technician_id,status,channel,requested_by,requested_at,manager_note,updated_at)
  values(p_job_id,v_job.customer_id,v_job.technician_id,'requested',p_channel,auth.uid(),now(),nullif(trim(coalesce(p_note,'')),''),now())
  on conflict(job_id) do update set status='requested',channel=excluded.channel,requested_by=auth.uid(),requested_at=now(),manager_note=excluded.manager_note,updated_at=now() returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(auth.uid(),'review_request_recorded','customer_review_request',v_id,jsonb_build_object('job_id',p_job_id,'channel',p_channel));
  return jsonb_build_object('id',v_id,'status','requested');
end;$$;

create or replace function private.record_customer_review_result_impl(p_job_id uuid,p_rating integer,p_feedback text default null,p_platform text default null,p_external_url text default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job public.jobs%rowtype; v_id uuid;
begin
  if not public.has_permission_for_current_user('manage_csr') and not public.has_permission_for_current_user('manage_customers') then raise exception 'Review result permission required'; end if;
  if p_rating is null or p_rating<1 or p_rating>5 then raise exception 'Rating must be between 1 and 5'; end if;
  select * into v_job from public.jobs where id=p_job_id;
  if not found then raise exception 'Job not found'; end if;
  insert into public.customer_review_requests(job_id,customer_id,technician_id,status,rating,feedback,review_platform,external_review_url,review_received_at,manager_note,updated_at)
  values(p_job_id,v_job.customer_id,v_job.technician_id,'received',p_rating,nullif(trim(coalesce(p_feedback,'')),''),nullif(trim(coalesce(p_platform,'')),''),nullif(trim(coalesce(p_external_url,'')),''),now(),nullif(trim(coalesce(p_note,'')),''),now())
  on conflict(job_id) do update set status='received',rating=excluded.rating,feedback=excluded.feedback,review_platform=excluded.review_platform,external_review_url=excluded.external_review_url,review_received_at=now(),manager_note=coalesce(excluded.manager_note,public.customer_review_requests.manager_note),updated_at=now() returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(auth.uid(),'customer_review_recorded','customer_review_request',v_id,jsonb_build_object('job_id',p_job_id,'rating',p_rating,'platform',p_platform));
  return jsonb_build_object('id',v_id,'status','received');
end;$$;

create or replace function public.review_management_queue(p_days integer default 30) returns jsonb language sql security invoker set search_path='' as $$ select private.review_management_queue_impl(p_days) $$;
create or replace function public.record_customer_review_request(p_job_id uuid,p_channel text,p_note text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.record_customer_review_request_impl(p_job_id,p_channel,p_note) $$;
create or replace function public.record_customer_review_result(p_job_id uuid,p_rating integer,p_feedback text default null,p_platform text default null,p_external_url text default null,p_note text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.record_customer_review_result_impl(p_job_id,p_rating,p_feedback,p_platform,p_external_url,p_note) $$;

revoke all on function private.review_management_queue_impl(integer) from public,anon;
revoke all on function private.record_customer_review_request_impl(uuid,text,text) from public,anon;
revoke all on function private.record_customer_review_result_impl(uuid,integer,text,text,text,text) from public,anon;
grant execute on function private.review_management_queue_impl(integer) to authenticated;
grant execute on function private.record_customer_review_request_impl(uuid,text,text) to authenticated;
grant execute on function private.record_customer_review_result_impl(uuid,integer,text,text,text,text) to authenticated;
revoke all on function public.review_management_queue(integer) from public,anon;
revoke all on function public.record_customer_review_request(uuid,text,text) from public,anon;
revoke all on function public.record_customer_review_result(uuid,integer,text,text,text,text) from public,anon;
grant execute on function public.review_management_queue(integer) to authenticated;
grant execute on function public.record_customer_review_request(uuid,text,text) to authenticated;
grant execute on function public.record_customer_review_result(uuid,integer,text,text,text,text) to authenticated;