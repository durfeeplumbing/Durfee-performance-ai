-- Zero-dollar invoices require explicit owner/manager approval before field closeout.
-- RPCs are authenticated-only and security-definer functions use an empty search_path.

create or replace function public.request_zero_invoice_closeout_approval(p_job_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_job public.jobs%rowtype; v_invoice_count bigint; v_invoice_total numeric; v_id uuid;
begin
  if not public.has_permission_for_current_user('field_app') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.technician_id is distinct from v_actor and not public.has_permission_for_current_user('manage_jobs') then raise exception 'Field users can only request approval for their assigned jobs'; end if;
  select count(*),coalesce(sum(total),0) into v_invoice_count,v_invoice_total from public.invoices where job_id=p_job_id;
  if v_invoice_count=0 then raise exception 'No invoice exists for this job'; end if;
  if v_invoice_total<>0 then raise exception 'Manager approval is only required for a zero-dollar invoice'; end if;
  insert into public.zero_invoice_closeout_approvals(job_id,status,requested_by,requested_at,approved_by,approved_at,rejected_by,rejected_at,manager_note,consumed_at,updated_at)
  values(p_job_id,'requested',v_actor,now(),null,null,null,null,null,null,now())
  on conflict(job_id) do update set status='requested',requested_by=excluded.requested_by,requested_at=now(),approved_by=null,approved_at=null,rejected_by=null,rejected_at=null,manager_note=null,consumed_at=null,updated_at=now() returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'request_zero_invoice_closeout_approval','job',p_job_id::text,jsonb_build_object('invoice_total',v_invoice_total,'status','requested'));
  return v_id;
end; $$;

create or replace function public.approve_zero_invoice_closeout(p_job_id uuid,p_manager_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_role text; v_invoice_count bigint; v_invoice_total numeric; v_id uuid;
begin
  select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if v_role not in ('owner','manager') then raise exception 'Owner or manager approval required'; end if;
  if not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_billing')) then raise exception 'Manager permission required'; end if;
  select count(*),coalesce(sum(total),0) into v_invoice_count,v_invoice_total from public.invoices where job_id=p_job_id;
  if v_invoice_count=0 or v_invoice_total<>0 then raise exception 'Job no longer has a zero-dollar invoice'; end if;
  update public.zero_invoice_closeout_approvals set status='approved',approved_by=v_actor,approved_at=now(),rejected_by=null,rejected_at=null,manager_note=nullif(btrim(coalesce(p_manager_note,'')),''),consumed_at=null,updated_at=now() where job_id=p_job_id and status='requested' returning id into v_id;
  if v_id is null then raise exception 'No pending zero-dollar closeout request exists'; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'approve_zero_invoice_closeout','job',p_job_id::text,jsonb_build_object('invoice_total',v_invoice_total,'status','approved','manager_note',nullif(btrim(coalesce(p_manager_note,'')),'')));
  return v_id;
end; $$;

create or replace function public.reject_zero_invoice_closeout(p_job_id uuid,p_manager_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_role text; v_id uuid;
begin
  select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if v_role not in ('owner','manager') then raise exception 'Owner or manager action required'; end if;
  if not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_billing')) then raise exception 'Manager permission required'; end if;
  update public.zero_invoice_closeout_approvals set status='rejected',rejected_by=v_actor,rejected_at=now(),approved_by=null,approved_at=null,manager_note=nullif(btrim(coalesce(p_manager_note,'')),''),consumed_at=null,updated_at=now() where job_id=p_job_id and status='requested' returning id into v_id;
  if v_id is null then raise exception 'No pending zero-dollar closeout request exists'; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'reject_zero_invoice_closeout','job',p_job_id::text,jsonb_build_object('status','rejected','manager_note',nullif(btrim(coalesce(p_manager_note,'')),'')));
  return v_id;
end; $$;

create or replace function public.zero_invoice_closeout_queue()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_billing')) then raise exception 'Manager permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('jobId',a.job_id,'status',a.status,'requestedAt',a.requested_at,'requestedBy',ru.name,'customerName',c.name,'serviceAddress',c.service_address,'serviceType',j.service_type,'serviceSummary',j.service_summary,'technicianName',tu.name,'invoiceTotal',coalesce(i.invoice_total,0),'managerNote',a.manager_note) order by a.requested_at asc),'[]'::jsonb) into v_result
  from public.zero_invoice_closeout_approvals a join public.jobs j on j.id=a.job_id left join public.customers c on c.id=j.customer_id left join public.users ru on ru.id=a.requested_by left join public.users tu on tu.id=j.technician_id left join lateral (select sum(total) invoice_total from public.invoices where job_id=j.id) i on true where a.status='requested' and a.consumed_at is null;
  return v_result;
end; $$;

revoke execute on function public.request_zero_invoice_closeout_approval(uuid) from public,anon;
revoke execute on function public.approve_zero_invoice_closeout(uuid,text) from public,anon;
revoke execute on function public.reject_zero_invoice_closeout(uuid,text) from public,anon;
revoke execute on function public.zero_invoice_closeout_queue() from public,anon;
grant execute on function public.request_zero_invoice_closeout_approval(uuid) to authenticated;
grant execute on function public.approve_zero_invoice_closeout(uuid,text) to authenticated;
grant execute on function public.reject_zero_invoice_closeout(uuid,text) to authenticated;
grant execute on function public.zero_invoice_closeout_queue() to authenticated;
