alter function public.create_job_material_stage(uuid,uuid,uuid,numeric,text) rename to create_job_material_stage_impl;
revoke all on function public.create_job_material_stage_impl(uuid,uuid,uuid,numeric,text) from public,anon,authenticated;

create function public.create_job_material_stage(p_purchase_order_id uuid,p_job_id uuid,p_inventory_item_id uuid,p_quantity numeric,p_staging_location text) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare a public.users%rowtype; rid uuid;
begin
  select * into a from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if a.id is null or a.role not in ('owner','manager','accounting','csr_dispatch') then raise exception 'Not authorized'; end if;
  if not private.has_permission('manage_staging') then raise exception 'Permission denied'; end if;
  rid:=public.create_job_material_stage_impl(p_purchase_order_id,p_job_id,p_inventory_item_id,p_quantity,p_staging_location);
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(a.id,'create_job_material_stage','job_material_staging',rid::text,jsonb_build_object('purchase_order_id',p_purchase_order_id,'job_id',p_job_id,'inventory_item_id',p_inventory_item_id,'quantity',p_quantity,'staging_location',p_staging_location));
  return rid;
end$$;
revoke all on function public.create_job_material_stage(uuid,uuid,uuid,numeric,text) from public,anon;
grant execute on function public.create_job_material_stage(uuid,uuid,uuid,numeric,text) to authenticated;

-- Superseded by review_and_approve_vendor_bill, which posts a reconciled AP entry atomically.
revoke all on function public.approve_vendor_bill_draft(uuid) from public,anon,authenticated;