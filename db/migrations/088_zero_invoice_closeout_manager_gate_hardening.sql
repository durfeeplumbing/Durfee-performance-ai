-- Hard gate: field users cannot complete a job without an invoice, and any $0 invoice
-- requires an explicit, unconsumed manager approval. The implementation RPC is not
-- directly executable by authenticated clients.

create or replace function public.set_field_status_atomic_impl(p_job_id uuid, p_requested_status text, p_no_materials boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid; v_job public.jobs%rowtype; v_next text; v_work_count bigint;
  v_material_count bigint; v_note_count bigint; v_invoice_count bigint;
  v_invoice_total numeric; v_zero_approval_id uuid;
begin
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.technician_id is distinct from v_actor and not (private.has_permission('manage_jobs') or private.has_permission('manage_dispatch')) then raise exception 'Field users can only update their assigned jobs'; end if;
  if p_requested_status='en_route' then
    if v_job.status not in ('scheduled','dispatched') then raise exception 'Job must be dispatched before going en route'; end if; v_next:='en_route';
  elsif p_requested_status='on_site' then
    if v_job.status<>'en_route' then raise exception 'Mark the job En Route before On Site'; end if; v_next:='on_site';
  elsif p_requested_status='work_complete' then
    if v_job.status<>'on_site' then raise exception 'Mark the job On Site before completing work'; end if;
    select count(*) into v_work_count from public.time_entries where job_id=p_job_id and entry_type='work';
    select count(*) into v_material_count from public.material_usage where job_id=p_job_id;
    select count(*) into v_note_count from public.job_notes where job_id=p_job_id and note_type='completion';
    if v_work_count=0 then raise exception 'Work time is required before completion'; end if;
    if v_note_count=0 then raise exception 'A completion note is required before completion'; end if;
    if v_material_count=0 and not p_no_materials then raise exception 'Record material usage or confirm that no materials were used'; end if;
    select count(*),coalesce(sum(total),0) into v_invoice_count,v_invoice_total from public.invoices where job_id=p_job_id;
    if v_invoice_count=0 then raise exception 'An invoice is required before job closeout'; end if;
    if v_invoice_total=0 then
      select id into v_zero_approval_id from public.zero_invoice_closeout_approvals
      where job_id=p_job_id and status='approved' and approved_by is not null and approved_at is not null and consumed_at is null for update;
      if v_zero_approval_id is null then raise exception 'Manager approval is required before closing a job with a $0 invoice'; end if;
    end if;
    if v_material_count=0 and p_no_materials then insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'confirm_no_materials','job',p_job_id::text,jsonb_build_object('no_materials',true)); end if;
    v_next:='completed';
  else raise exception 'Invalid status'; end if;
  update public.jobs set status=v_next,completed_at=case when v_next='completed' then now() else completed_at end where id=p_job_id;
  if v_next='completed' and v_zero_approval_id is not null then update public.zero_invoice_closeout_approvals set consumed_at=now(),updated_at=now() where id=v_zero_approval_id; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_actor,'field_status_change','job',p_job_id::text,jsonb_build_object('status',v_job.status),jsonb_build_object('status',v_next,'zero_invoice_approval_id',v_zero_approval_id));
  return p_job_id;
end;$$;
revoke execute on function public.set_field_status_atomic_impl(uuid,text,boolean) from public,anon,authenticated;

create or replace function public.set_field_status_atomic(p_job_id uuid,p_requested_status text,p_no_materials boolean)
returns uuid language plpgsql security definer set search_path='' as $$
begin
  if not private.has_permission('field_app') then raise exception 'Permission denied'; end if;
  return public.set_field_status_atomic_impl(p_job_id,p_requested_status,p_no_materials);
end;$$;
revoke execute on function public.set_field_status_atomic(uuid,text,boolean) from public,anon;
grant execute on function public.set_field_status_atomic(uuid,text,boolean) to authenticated;

create or replace function public.approve_zero_invoice_closeout(p_job_id uuid,p_manager_note text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_invoice_count bigint; v_invoice_total numeric; v_id uuid;
begin
  if not (private.has_permission('manage_jobs') or private.has_permission('manage_billing')) then raise exception 'Manager permission required'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  select count(*),coalesce(sum(total),0) into v_invoice_count,v_invoice_total from public.invoices where job_id=p_job_id;
  if v_invoice_count=0 or v_invoice_total<>0 then raise exception 'Job no longer has a zero-dollar invoice'; end if;
  update public.zero_invoice_closeout_approvals set status='approved',approved_by=v_actor,approved_at=now(),rejected_by=null,rejected_at=null,manager_note=nullif(btrim(coalesce(p_manager_note,'')),''),consumed_at=null,updated_at=now() where job_id=p_job_id and status='requested' returning id into v_id;
  if v_id is null then raise exception 'No pending zero-dollar closeout request exists'; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'approve_zero_invoice_closeout','job',p_job_id::text,jsonb_build_object('invoice_total',v_invoice_total,'status','approved','manager_note',nullif(btrim(coalesce(p_manager_note,'')),'')));
  return v_id;
end;$$;
revoke execute on function public.approve_zero_invoice_closeout(uuid,text) from public,anon;
grant execute on function public.approve_zero_invoice_closeout(uuid,text) to authenticated;
