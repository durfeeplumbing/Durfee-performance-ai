create or replace function public.assign_technician_atomic(p_job_id uuid,p_technician_id uuid default null)
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
  v_next_status text;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','csr_dispatch') then raise exception 'Not authorized'; end if;

  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;

  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.status not in ('booked','scheduled','dispatched') then
    raise exception 'Technician assignment cannot be changed after field work starts or the job is closed';
  end if;

  if p_technician_id is not null then
    select * into v_tech from public.users where id=p_technician_id and role='technician' and active=true;
    if not found then raise exception 'Active technician required'; end if;

    if v_job.service_type is not null then
      select * into v_skill
      from public.technician_skills
      where technician_id=p_technician_id
        and skill=v_job.service_type
        and active=true
      limit 1;
      if not found then raise exception 'Technician is not eligible for this service'; end if;
      if v_skill.certification_expires_on is not null and v_skill.certification_expires_on < current_date then
        raise exception 'Technician certification has expired';
      end if;
    end if;
    v_next_status:='dispatched';
  else
    v_next_status:='scheduled';
  end if;

  update public.jobs
  set technician_id=p_technician_id,status=v_next_status
  where id=p_job_id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(
    v_actor,
    case when p_technician_id is null then 'unassign_technician' else 'assign_technician' end,
    'job',
    p_job_id::text,
    jsonb_build_object('technician_id',v_job.technician_id,'status',v_job.status),
    jsonb_build_object('technician_id',p_technician_id,'status',v_next_status,'source','manual_dispatch')
  );

  return p_job_id;
end;
$$;

revoke all on function public.assign_technician_atomic(uuid,uuid) from public;
grant execute on function public.assign_technician_atomic(uuid,uuid) to authenticated;
