create or replace function public.set_field_status_atomic(
  p_job_id uuid,
  p_requested_status text,
  p_no_materials boolean default false
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
  v_next text;
  v_work_count bigint;
  v_material_count bigint;
  v_note_count bigint;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('technician','owner','manager') then raise exception 'Field actions are restricted to technicians and field management'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;

  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_role='technician' and v_job.technician_id is distinct from v_actor then raise exception 'Technicians can only update their assigned jobs'; end if;

  if p_requested_status='en_route' then
    if v_job.status not in ('scheduled','dispatched') then raise exception 'Job must be dispatched before going en route'; end if;
    v_next:='en_route';
  elsif p_requested_status='on_site' then
    if v_job.status<>'en_route' then raise exception 'Mark the job En Route before On Site'; end if;
    v_next:='on_site';
  elsif p_requested_status='work_complete' then
    if v_job.status<>'on_site' then raise exception 'Mark the job On Site before completing work'; end if;
    select count(*) into v_work_count from public.time_entries where job_id=p_job_id and entry_type='work';
    select count(*) into v_material_count from public.material_usage where job_id=p_job_id;
    select count(*) into v_note_count from public.job_notes where job_id=p_job_id and note_type='completion';
    if v_work_count=0 then raise exception 'Work time is required before completion'; end if;
    if v_note_count=0 then raise exception 'A completion note is required before completion'; end if;
    if v_material_count=0 and not p_no_materials then raise exception 'Record material usage or confirm that no materials were used'; end if;
    if v_material_count=0 and p_no_materials then
      insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
      values(v_actor,'confirm_no_materials','job',p_job_id::text,jsonb_build_object('no_materials',true));
    end if;
    v_next:='completed';
  else
    raise exception 'Invalid status';
  end if;

  update public.jobs
  set status=v_next,
      completed_at=case when v_next='completed' then now() else completed_at end
  where id=p_job_id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(v_actor,'field_status_change','job',p_job_id::text,jsonb_build_object('status',v_job.status),jsonb_build_object('status',v_next));
  return p_job_id;
end;
$$;

create or replace function public.add_work_time_atomic(
  p_job_id uuid,
  p_hours numeric
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
  v_entry_id uuid;
  v_ended timestamptz:=now();
  v_started timestamptz;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('technician','owner','manager') then raise exception 'Field actions are restricted to technicians and field management'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_hours is null or p_hours<=0 or p_hours>24 then raise exception 'Enter valid hours'; end if;

  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_role='technician' and v_job.technician_id is distinct from v_actor then raise exception 'Technicians can only update their assigned jobs'; end if;
  if v_job.status<>'on_site' then raise exception 'Mark the job On Site before recording work time'; end if;
  if v_job.technician_id is null then raise exception 'Assign a technician before recording work time'; end if;

  v_started:=v_ended-(p_hours * interval '1 hour');
  insert into public.time_entries(job_id,technician_id,entry_type,started_at,ended_at)
  values(p_job_id,v_job.technician_id,'work',v_started,v_ended)
  returning id into v_entry_id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(v_actor,'add_work_time','job',p_job_id::text,jsonb_build_object('time_entry_id',v_entry_id,'technician_id',v_job.technician_id,'hours',p_hours,'started_at',v_started,'ended_at',v_ended));
  return v_entry_id;
end;
$$;

revoke all on function public.set_field_status_atomic(uuid,text,boolean) from public;
grant execute on function public.set_field_status_atomic(uuid,text,boolean) to authenticated;
revoke all on function public.add_work_time_atomic(uuid,numeric) from public;
grant execute on function public.add_work_time_atomic(uuid,numeric) to authenticated;
