do $$
declare r record; d text; original text;
begin
  for r in
    select p.oid,p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'add_customer_equipment_atomic_impl','add_estimate_option_atomic_impl','add_field_material_atomic_impl','add_job_note_atomic_impl','add_work_time_atomic_impl',
      'allocate_ap_to_job_impl','approve_estimate_option_internal_impl','close_job_financially_impl','consume_inventory_for_job_impl','create_customer_atomic_impl',
      'create_estimate_acceptance_link_atomic_impl','create_estimate_atomic_impl','create_inventory_item_atomic_impl','create_job_invoice_explicit_impl','create_job_material_stage_impl',
      'create_purchase_order_impl','finalize_job_photo_atomic_impl','finalize_purchase_order_document_atomic_impl','receive_purchase_order_line_impl','record_ap_payment_impl',
      'record_invoice_payment_impl','reject_vendor_bill_atomic_impl','review_and_approve_vendor_bill_impl','revoke_estimate_acceptance_link_atomic_impl',
      'save_technician_skill_atomic_impl','set_field_status_atomic_impl','update_customer_verified_address_atomic_impl','update_inventory_item_atomic_impl'
    )
  loop
    original:=pg_get_functiondef(r.oid); d:=original;

    -- Permission wrappers are the authorization boundary. Keep identity checks and business-rule checks in implementations.
    d:=regexp_replace(d,E"if\\s+v_role\\s+not\\s+in\\s*\\([^)]*\\)\\s+then\\s+raise\\s+exception\\s+'[^']*';\\s*end\\s+if;",'', 'i');
    d:=regexp_replace(d,E"if\\s+v_actor\\s+is\\s+null\\s+or\\s+v_role\\s+not\\s+in\\s*\\([^)]*\\)\\s+then\\s+raise\\s+exception\\s+'Not authorized';\\s*end\\s+if;",E"if v_actor is null then raise exception 'Employee identity unavailable'; end if;", 'i');
    d:=regexp_replace(d,E"if\\s+v_user\\.id\\s+is\\s+null\\s+or\\s+v_user\\.role\\s+not\\s+in\\s*\\([^)]*\\)\\s+then\\s+raise\\s+exception\\s+'Not authorized';\\s*end\\s+if;",E"if v_user.id is null then raise exception 'Employee identity unavailable'; end if;", 'i');
    d:=regexp_replace(d,E"if\\s+u\\.id\\s+is\\s+null\\s+or\\s+u\\.role\\s+not\\s+in\\s*\\([^)]*\\)\\s+then\\s+raise\\s+exception\\s+'Not authorized';\\s*end\\s+if;",E"if u.id is null then raise exception 'Employee identity unavailable'; end if;", 'i');
    d:=regexp_replace(d,E"if\\s+actor\\.id\\s+is\\s+null\\s+or\\s+actor\\.role\\s+not\\s+in\\s*\\([^)]*\\)\\s+then\\s+raise\\s+exception\\s+'Not authorized';\\s*end\\s+if;",E"if actor.id is null then raise exception 'Employee identity unavailable'; end if;", 'i');

    -- Users with field_app may act only on their assigned job unless they also have management authority.
    d:=regexp_replace(d,E"if\\s+v_role='technician'\\s+and\\s+v_job\\.technician_id\\s+is\\s+distinct\\s+from\\s+v_actor\\s+then\\s+raise\\s+exception\\s+'[^']*';\\s*end\\s+if;",E"if v_job.technician_id is distinct from v_actor and not (private.has_permission('manage_jobs') or private.has_permission('manage_dispatch')) then raise exception 'Field users can only update their assigned jobs'; end if;", 'i');
    d:=regexp_replace(d,E"if\\s+v_user\\.role='technician'\\s+and\\s+v_job\\.technician_id\\s+is\\s+distinct\\s+from\\s+v_user\\.id\\s+then\\s+raise\\s+exception\\s+'[^']*';\\s*end\\s+if;",E"if v_job.technician_id is distinct from v_user.id and not (private.has_permission('manage_jobs') or private.has_permission('manage_dispatch')) then raise exception 'Field users can only update their assigned jobs'; end if;", 'i');

    if d=original then
      raise exception 'Expected authorization guard not found in %',r.proname;
    end if;
    execute d;
  end loop;
end $$;

-- Staging wrapper also had a historical fixed-role gate. Permission is now authoritative.
create or replace function public.create_job_material_stage(p_purchase_order_id uuid,p_job_id uuid,p_inventory_item_id uuid,p_quantity numeric,p_staging_location text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare a public.users%rowtype; rid uuid;
begin
  if not private.has_permission('manage_staging') then raise exception 'Permission denied'; end if;
  select * into a from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if a.id is null then raise exception 'Employee identity unavailable'; end if;
  rid:=public.create_job_material_stage_impl(p_purchase_order_id,p_job_id,p_inventory_item_id,p_quantity,p_staging_location);
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(a.id,'create_job_material_stage','job_material_staging',rid::text,jsonb_build_object('purchase_order_id',p_purchase_order_id,'job_id',p_job_id,'inventory_item_id',p_inventory_item_id,'quantity',p_quantity,'staging_location',p_staging_location));
  return rid;
end$$;

revoke all on function public.create_job_material_stage(uuid,uuid,uuid,numeric,text) from public,anon;
grant execute on function public.create_job_material_stage(uuid,uuid,uuid,numeric,text) to authenticated;

-- Implementation functions are never API entrypoints.
do $$
declare r record;
begin
 for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%_impl'
 loop execute format('revoke all on function %s from public,anon,authenticated',r.sig); end loop;
end $$;
