-- Low-GP closeout manager approval guard.
-- Live database behavior:
--   * Uses company_pricing_settings.minimum_gp (default 50) rather than a hard-coded target.
--   * Revenue is the sum of job invoice totals.
--   * Cost includes jobs.material_cost + labor_cost + allocated_overhead plus active
--     non-material job_cost_allocations. Material AP allocations are already rolled into
--     jobs.material_cost and therefore are intentionally not counted twice.
--   * A below-floor approval is single-use and bound to a revenue/cost/minimum-GP snapshot.
--   * Any economics or target change invalidates the approval and requires re-review.
--   * Field users receive pass/review status only; detailed cost/GP is returned only to
--     users with finance/pricing access.

create table if not exists public.gp_closeout_approvals (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null unique references public.jobs(id) on delete cascade,
  status text not null check (status in ('requested','approved','rejected')),
  requested_by uuid not null references public.users(id),
  requested_at timestamptz not null default now(),
  approved_by uuid references public.users(id),
  approved_at timestamptz,
  rejected_by uuid references public.users(id),
  rejected_at timestamptz,
  manager_note text,
  revenue_snapshot numeric not null default 0,
  cost_snapshot numeric not null default 0,
  gp_snapshot numeric,
  minimum_gp_snapshot numeric not null default 50,
  consumed_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.gp_closeout_approvals enable row level security;
revoke all on table public.gp_closeout_approvals from anon, authenticated;

create or replace function public.request_gp_closeout_approval(p_job_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid; v_job public.jobs%rowtype; v_invoice_total numeric; v_extra_cost numeric;
  v_cost numeric; v_gp numeric; v_floor numeric; v_id uuid;
begin
  if not public.has_permission_for_current_user('field_app') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.technician_id is distinct from v_actor and not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_dispatch')) then raise exception 'Field users can only request approval for their assigned jobs'; end if;
  select coalesce(sum(total),0) into v_invoice_total from public.invoices where job_id=p_job_id;
  if v_invoice_total<=0 then raise exception 'Low-GP approval requires a positive invoice total'; end if;
  select coalesce(sum(amount),0) into v_extra_cost from public.job_cost_allocations where job_id=p_job_id and reversed_at is null and allocation_type<>'materials';
  select minimum_gp into v_floor from public.company_pricing_settings where id=true; v_floor:=coalesce(v_floor,50);
  v_cost:=coalesce(v_job.material_cost,0)+coalesce(v_job.labor_cost,0)+coalesce(v_job.allocated_overhead,0)+v_extra_cost;
  v_gp:=((v_invoice_total-v_cost)/v_invoice_total)*100;
  if v_gp>=v_floor then raise exception 'Job is at or above the minimum GP and does not require approval'; end if;
  insert into public.gp_closeout_approvals(job_id,status,requested_by,requested_at,approved_by,approved_at,rejected_by,rejected_at,manager_note,revenue_snapshot,cost_snapshot,gp_snapshot,minimum_gp_snapshot,consumed_at,updated_at)
  values(p_job_id,'requested',v_actor,now(),null,null,null,null,null,v_invoice_total,v_cost,v_gp,v_floor,null,now())
  on conflict(job_id) do update set status='requested',requested_by=excluded.requested_by,requested_at=now(),approved_by=null,approved_at=null,rejected_by=null,rejected_at=null,manager_note=null,revenue_snapshot=excluded.revenue_snapshot,cost_snapshot=excluded.cost_snapshot,gp_snapshot=excluded.gp_snapshot,minimum_gp_snapshot=excluded.minimum_gp_snapshot,consumed_at=null,updated_at=now()
  returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'request_gp_closeout_approval','job',p_job_id::text,jsonb_build_object('revenue',v_invoice_total,'cost',v_cost,'gp',v_gp,'minimum_gp',v_floor));
  return v_id;
end;$$;

create or replace function public.approve_gp_closeout(p_job_id uuid,p_manager_note text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid; v_role text; v_job public.jobs%rowtype; v_invoice_total numeric; v_extra_cost numeric;
  v_cost numeric; v_gp numeric; v_floor numeric; v_id uuid;
begin
  select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if v_role not in ('owner','manager') then raise exception 'Owner or manager approval required'; end if;
  if not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_billing')) then raise exception 'Manager permission required'; end if;
  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  select coalesce(sum(total),0) into v_invoice_total from public.invoices where job_id=p_job_id;
  if v_invoice_total<=0 then raise exception 'Job does not have positive billable revenue'; end if;
  select coalesce(sum(amount),0) into v_extra_cost from public.job_cost_allocations where job_id=p_job_id and reversed_at is null and allocation_type<>'materials';
  select minimum_gp into v_floor from public.company_pricing_settings where id=true; v_floor:=coalesce(v_floor,50);
  v_cost:=coalesce(v_job.material_cost,0)+coalesce(v_job.labor_cost,0)+coalesce(v_job.allocated_overhead,0)+v_extra_cost;
  v_gp:=((v_invoice_total-v_cost)/v_invoice_total)*100;
  if v_gp>=v_floor then raise exception 'Job is now at or above the minimum GP; approval is no longer required'; end if;
  update public.gp_closeout_approvals set status='approved',approved_by=v_actor,approved_at=now(),rejected_by=null,rejected_at=null,manager_note=nullif(btrim(coalesce(p_manager_note,'')),''),revenue_snapshot=v_invoice_total,cost_snapshot=v_cost,gp_snapshot=v_gp,minimum_gp_snapshot=v_floor,consumed_at=null,updated_at=now() where job_id=p_job_id and status='requested' returning id into v_id;
  if v_id is null then raise exception 'No pending low-GP closeout request exists'; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'approve_gp_closeout','job',p_job_id::text,jsonb_build_object('revenue',v_invoice_total,'cost',v_cost,'gp',v_gp,'minimum_gp',v_floor,'manager_note',nullif(btrim(coalesce(p_manager_note,'')),'')));
  return v_id;
end;$$;

create or replace function public.reject_gp_closeout(p_job_id uuid,p_manager_note text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_role text; v_id uuid;
begin
  select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if v_role not in ('owner','manager') then raise exception 'Owner or manager action required'; end if;
  if not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_billing')) then raise exception 'Manager permission required'; end if;
  update public.gp_closeout_approvals set status='rejected',rejected_by=v_actor,rejected_at=now(),approved_by=null,approved_at=null,manager_note=nullif(btrim(coalesce(p_manager_note,'')),''),consumed_at=null,updated_at=now() where job_id=p_job_id and status='requested' returning id into v_id;
  if v_id is null then raise exception 'No pending low-GP closeout request exists'; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'reject_gp_closeout','job',p_job_id::text,jsonb_build_object('status','rejected','manager_note',nullif(btrim(coalesce(p_manager_note,'')),'')));
  return v_id;
end;$$;

create or replace function public.gp_closeout_queue()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_billing')) then raise exception 'Manager permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('jobId',a.job_id,'status',a.status,'requestedAt',a.requested_at,'requestedBy',ru.name,'customerName',c.name,'serviceAddress',c.service_address,'serviceType',j.service_type,'serviceSummary',j.service_summary,'technicianName',tu.name,'revenue',a.revenue_snapshot,'cost',a.cost_snapshot,'gp',a.gp_snapshot,'minimumGp',a.minimum_gp_snapshot,'managerNote',a.manager_note) order by a.requested_at asc),'[]'::jsonb) into v_result
  from public.gp_closeout_approvals a join public.jobs j on j.id=a.job_id left join public.customers c on c.id=j.customer_id left join public.users ru on ru.id=a.requested_by left join public.users tu on tu.id=j.technician_id where a.status='requested' and a.consumed_at is null;
  return v_result;
end;$$;

create or replace function public.field_closeout_economics()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_actor uuid; v_can_manage boolean; v_can_finance boolean; v_floor numeric; v_result jsonb;
begin
  if not public.has_permission_for_current_user('field_app') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  v_can_manage:=public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_dispatch');
  v_can_finance:=public.has_permission_for_current_user('manage_billing') or public.has_permission_for_current_user('manage_pricing_settings');
  select minimum_gp into v_floor from public.company_pricing_settings where id=true; v_floor:=coalesce(v_floor,50);
  select coalesce(jsonb_agg(jsonb_build_object('jobId',j.id,'invoiceTotal',case when v_can_finance then x.invoice_total else null end,'totalCost',case when v_can_finance then x.total_cost else null end,'gp',case when v_can_finance and x.invoice_total>0 then ((x.invoice_total-x.total_cost)/x.invoice_total)*100 else null end,'minimumGp',v_floor,'hasPositiveInvoice',x.invoice_total>0,'requiresGpApproval',x.invoice_total>0 and ((x.invoice_total-x.total_cost)/x.invoice_total)*100<v_floor,'approvalStatus',case when a.consumed_at is not null then 'consumed' else a.status end,'approvedSnapshotMatches',coalesce(a.status='approved' and a.consumed_at is null and abs(a.revenue_snapshot-x.invoice_total)<0.01 and abs(a.cost_snapshot-x.total_cost)<0.01 and abs(a.minimum_gp_snapshot-v_floor)<0.01,false))),'[]'::jsonb) into v_result
  from public.jobs j
  cross join lateral (select coalesce((select sum(i.total) from public.invoices i where i.job_id=j.id),0)::numeric invoice_total,(coalesce(j.material_cost,0)+coalesce(j.labor_cost,0)+coalesce(j.allocated_overhead,0)+coalesce((select sum(a2.amount) from public.job_cost_allocations a2 where a2.job_id=j.id and a2.reversed_at is null and a2.allocation_type<>'materials'),0))::numeric total_cost) x
  left join public.gp_closeout_approvals a on a.job_id=j.id
  where j.status in ('scheduled','dispatched','en_route','on_site') and (j.technician_id=v_actor or v_can_manage);
  return v_result;
end;$$;

-- This definition deliberately preserves the existing zero-dollar approval gate while
-- adding the below-GP snapshot gate.
create or replace function public.set_field_status_atomic_impl(p_job_id uuid,p_requested_status text,p_no_materials boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid; v_job public.jobs%rowtype; v_next text; v_work_count bigint; v_material_count bigint; v_note_count bigint;
  v_invoice_count bigint; v_invoice_total numeric; v_zero_approval_id uuid; v_gp_approval_id uuid; v_extra_cost numeric; v_cost numeric; v_gp numeric; v_floor numeric;
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
      select id into v_zero_approval_id from public.zero_invoice_closeout_approvals where job_id=p_job_id and status='approved' and approved_by is not null and approved_at is not null and consumed_at is null for update;
      if v_zero_approval_id is null then raise exception 'Manager approval is required before closing a job with a $0 invoice'; end if;
    else
      select coalesce(sum(amount),0) into v_extra_cost from public.job_cost_allocations where job_id=p_job_id and reversed_at is null and allocation_type<>'materials';
      select minimum_gp into v_floor from public.company_pricing_settings where id=true; v_floor:=coalesce(v_floor,50);
      v_cost:=coalesce(v_job.material_cost,0)+coalesce(v_job.labor_cost,0)+coalesce(v_job.allocated_overhead,0)+v_extra_cost;
      v_gp:=((v_invoice_total-v_cost)/v_invoice_total)*100;
      if v_gp<v_floor then
        select id into v_gp_approval_id from public.gp_closeout_approvals where job_id=p_job_id and status='approved' and approved_by is not null and approved_at is not null and consumed_at is null and abs(revenue_snapshot-v_invoice_total)<0.01 and abs(cost_snapshot-v_cost)<0.01 and abs(minimum_gp_snapshot-v_floor)<0.01 for update;
        if v_gp_approval_id is null then raise exception 'Manager approval is required before closing a job below the minimum gross profit target'; end if;
      end if;
    end if;
    if v_material_count=0 and p_no_materials then insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'confirm_no_materials','job',p_job_id::text,jsonb_build_object('no_materials',true)); end if;
    v_next:='completed';
  else raise exception 'Invalid status'; end if;
  update public.jobs set status=v_next,completed_at=case when v_next='completed' then now() else completed_at end where id=p_job_id;
  if v_next='completed' and v_zero_approval_id is not null then update public.zero_invoice_closeout_approvals set consumed_at=now(),updated_at=now() where id=v_zero_approval_id; end if;
  if v_next='completed' and v_gp_approval_id is not null then update public.gp_closeout_approvals set consumed_at=now(),updated_at=now() where id=v_gp_approval_id; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_actor,'field_status_change','job',p_job_id::text,jsonb_build_object('status',v_job.status),jsonb_build_object('status',v_next,'zero_invoice_approval_id',v_zero_approval_id,'gp_approval_id',v_gp_approval_id,'closeout_gp',v_gp,'minimum_gp',v_floor));
  return p_job_id;
end;$$;

revoke execute on function public.request_gp_closeout_approval(uuid) from public,anon;
revoke execute on function public.approve_gp_closeout(uuid,text) from public,anon;
revoke execute on function public.reject_gp_closeout(uuid,text) from public,anon;
revoke execute on function public.gp_closeout_queue() from public,anon;
revoke execute on function public.field_closeout_economics() from public,anon;
revoke execute on function public.set_field_status_atomic_impl(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.request_gp_closeout_approval(uuid) to authenticated;
grant execute on function public.approve_gp_closeout(uuid,text) to authenticated;
grant execute on function public.reject_gp_closeout(uuid,text) to authenticated;
grant execute on function public.gp_closeout_queue() to authenticated;
grant execute on function public.field_closeout_economics() to authenticated;
