create or replace function public.reschedule_job_atomic(
  p_job_id uuid,
  p_scheduled_start timestamptz,
  p_scheduled_end timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_role text;
  v_actor uuid;
  v_job public.jobs%rowtype;
  v_next_status text;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','csr_dispatch') then raise exception 'Not authorized'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_scheduled_start is null then raise exception 'Schedule start required'; end if;
  if p_scheduled_end is not null and p_scheduled_end<=p_scheduled_start then raise exception 'Schedule end must be after start'; end if;

  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.status not in ('booked','scheduled','dispatched') then
    raise exception 'Schedule cannot be changed after field work starts or the job is closed';
  end if;

  v_next_status:=case when v_job.technician_id is null then 'scheduled' else 'dispatched' end;
  update public.jobs
  set scheduled_start=p_scheduled_start,
      scheduled_end=p_scheduled_end,
      status=v_next_status
  where id=p_job_id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(
    v_actor,'reschedule_job','job',p_job_id::text,
    jsonb_build_object('scheduled_start',v_job.scheduled_start,'scheduled_end',v_job.scheduled_end,'status',v_job.status),
    jsonb_build_object('scheduled_start',p_scheduled_start,'scheduled_end',p_scheduled_end,'status',v_next_status,'source','dispatcher')
  );
  return p_job_id;
end;
$$;

create or replace function public.cancel_job_atomic(
  p_job_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_role text;
  v_actor uuid;
  v_job public.jobs%rowtype;
  v_reason text;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','csr_dispatch') then raise exception 'Not authorized'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  v_reason:=btrim(coalesce(p_reason,''));
  if length(v_reason)<3 then raise exception 'Cancellation reason required'; end if;
  if length(v_reason)>1000 then raise exception 'Cancellation reason is too long'; end if;

  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.status not in ('booked','scheduled','dispatched') then
    raise exception 'Job cannot be cancelled after field work starts or after closeout';
  end if;

  update public.jobs
  set status='cancelled', technician_id=null
  where id=p_job_id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(
    v_actor,'cancel_job','job',p_job_id::text,
    jsonb_build_object('status',v_job.status,'technician_id',v_job.technician_id,'scheduled_start',v_job.scheduled_start,'scheduled_end',v_job.scheduled_end),
    jsonb_build_object('status','cancelled','reason',v_reason,'source','dispatcher')
  );
  return p_job_id;
end;
$$;

revoke all on function public.reschedule_job_atomic(uuid,timestamptz,timestamptz) from public;
revoke all on function public.cancel_job_atomic(uuid,text) from public;
grant execute on function public.reschedule_job_atomic(uuid,timestamptz,timestamptz) to authenticated;
grant execute on function public.cancel_job_atomic(uuid,text) to authenticated;
