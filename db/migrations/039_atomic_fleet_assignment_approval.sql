create or replace function public.approve_fleet_assignment_atomic(
  p_job_id uuid,
  p_technician_id uuid,
  p_expected_scheduled_start timestamptz,
  p_expected_scheduled_end timestamptz,
  p_recommended_start numeric,
  p_recommended_finish numeric,
  p_drive_in_minutes numeric,
  p_drive_to_next_minutes numeric,
  p_routing_source text,
  p_service_day_start timestamptz,
  p_service_day_end timestamptz
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
  v_tech public.users%rowtype;
  v_skill public.technician_skills%rowtype;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','csr_dispatch') then raise exception 'Not authorized'; end if;

  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;

  if p_technician_id is null then raise exception 'Technician required'; end if;
  if p_recommended_start is null or p_recommended_finish is null or p_recommended_finish<=p_recommended_start then
    raise exception 'Invalid fleet recommendation';
  end if;

  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.technician_id is not null then raise exception 'Job is already assigned; refresh the fleet plan'; end if;
  if v_job.status not in ('booked','scheduled','dispatched') then raise exception 'Job can no longer be dispatched'; end if;
  if v_job.scheduled_start is distinct from p_expected_scheduled_start or v_job.scheduled_end is distinct from p_expected_scheduled_end then
    raise exception 'Job schedule changed; refresh the fleet plan';
  end if;

  select * into v_tech from public.users where id=p_technician_id and role='technician' and active=true;
  if not found then raise exception 'Active technician required'; end if;

  if v_job.service_type is not null then
    select * into v_skill
    from public.technician_skills
    where technician_id=p_technician_id and skill=v_job.service_type and active=true
    limit 1;
    if not found then raise exception 'Technician is no longer eligible for this service'; end if;
    if v_skill.certification_expires_on is not null and v_skill.certification_expires_on < current_date then
      raise exception 'Technician certification has expired';
    end if;
  end if;

  update public.jobs set technician_id=p_technician_id,status='dispatched' where id=p_job_id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(
    v_actor,
    'approve_fleet_assignment',
    'job',
    p_job_id::text,
    jsonb_build_object('technician_id',v_job.technician_id,'status',v_job.status,'scheduled_start',v_job.scheduled_start,'scheduled_end',v_job.scheduled_end),
    jsonb_build_object(
      'technician_id',p_technician_id,
      'status','dispatched',
      'scheduled_start',v_job.scheduled_start,
      'scheduled_end',v_job.scheduled_end,
      'service_day_start',p_service_day_start,
      'service_day_end',p_service_day_end,
      'recommended_start',p_recommended_start,
      'recommended_finish',p_recommended_finish,
      'drive_in_minutes',p_drive_in_minutes,
      'drive_to_next_minutes',p_drive_to_next_minutes,
      'routing_source',p_routing_source,
      'source','fleet_optimizer'
    )
  );

  return p_job_id;
end;
$$;

revoke all on function public.approve_fleet_assignment_atomic(uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,text,timestamptz,timestamptz) from public;
grant execute on function public.approve_fleet_assignment_atomic(uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,text,timestamptz,timestamptz) to authenticated;
