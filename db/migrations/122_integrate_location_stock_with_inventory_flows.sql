create or replace function private.update_inventory_item_atomic_impl(p_id uuid,p_expected_on_hand numeric,p_expected_reorder_point numeric,p_expected_unit_cost numeric,p_on_hand numeric,p_reorder_point numeric,p_unit_cost numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid;v_item public.inventory_items%rowtype;v_delta numeric;v_has_location_stock boolean;
begin
  if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable';end if;
  if p_id is null or coalesce(p_on_hand,-1)<0 or coalesce(p_reorder_point,-1)<0 or coalesce(p_unit_cost,-1)<0 then raise exception 'Invalid inventory values';end if;
  select * into v_item from public.inventory_items where id=p_id for update;if not found then raise exception 'Inventory item not found';end if;
  if v_item.on_hand is distinct from p_expected_on_hand or v_item.reorder_point is distinct from p_expected_reorder_point or v_item.unit_cost is distinct from p_expected_unit_cost then raise exception 'Inventory item changed; refresh before saving';end if;
  v_delta:=p_on_hand-v_item.on_hand;
  select exists(select 1 from public.inventory_location_stock where inventory_item_id=p_id) into v_has_location_stock;
  if v_has_location_stock and v_delta<>0 then
    if v_item.location_id is null then raise exception 'Location stock is active; adjust inventory with a cycle count'; end if;
    if not exists(select 1 from public.inventory_location_stock where inventory_item_id=p_id and location_id=v_item.location_id) then raise exception 'Primary location stock is not initialized'; end if;
    if (select on_hand from public.inventory_location_stock where inventory_item_id=p_id and location_id=v_item.location_id)+v_delta<0 then raise exception 'Primary location cannot absorb this adjustment'; end if;
    update public.inventory_location_stock set on_hand=on_hand+v_delta,reorder_point=p_reorder_point,max_stock=v_item.max_stock,updated_at=now() where inventory_item_id=p_id and location_id=v_item.location_id;
  elsif v_has_location_stock then
    update public.inventory_location_stock set reorder_point=p_reorder_point,updated_at=now() where inventory_item_id=p_id and location_id=v_item.location_id;
  end if;
  update public.inventory_items set on_hand=p_on_hand,reorder_point=p_reorder_point,unit_cost=p_unit_cost where id=p_id;
  if v_delta<>0 then insert into public.inventory_transactions(inventory_item_id,location_id,transaction_type,quantity,unit_cost,actor_user_id) values(p_id,v_item.location_id,'adjustment',v_delta,p_unit_cost,v_actor);end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_actor,'update_inventory_item','inventory_item',p_id::text,jsonb_build_object('on_hand',v_item.on_hand,'reorder_point',v_item.reorder_point,'unit_cost',v_item.unit_cost),jsonb_build_object('on_hand',p_on_hand,'reorder_point',p_reorder_point,'unit_cost',p_unit_cost));return p_id;
end$$;

create or replace function private.receive_purchase_order_line_impl(p_line_id uuid,p_quantity numeric,p_location_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user public.users%rowtype;v_line public.purchase_order_items%rowtype;v_po public.purchase_orders%rowtype;v_loc public.inventory_locations%rowtype;v_item public.inventory_items%rowtype;v_tx uuid;v_new_status text;
begin
  if not private.has_permission('manage_purchasing') then raise exception 'Permission denied'; end if;
  select * into v_user from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_user.id is null then raise exception 'Employee identity unavailable'; end if;
  if p_quantity is null or p_quantity<=0 or p_line_id is null or p_location_id is null then raise exception 'Valid line, quantity and location required';end if;
  select * into v_loc from public.inventory_locations where id=p_location_id and active=true;if not found then raise exception 'Receiving location not found or inactive';end if;
  select * into v_line from public.purchase_order_items where id=p_line_id for update;if not found or v_line.inventory_item_id is null then raise exception 'Invalid PO line';end if;if v_line.received_quantity+p_quantity>v_line.quantity then raise exception 'Cannot receive more than ordered';end if;
  select * into v_po from public.purchase_orders where id=v_line.purchase_order_id for update;if not found then raise exception 'Purchase order not found';end if;if v_po.status not in ('draft','submitted','partial') then raise exception 'Purchase order cannot be received in its current state';end if;
  if not exists(select 1 from public.purchase_order_documents d where d.purchase_order_id=v_po.id and d.document_type='vendor_invoice') then raise exception 'Vendor invoice photo or PDF is required before receiving material';end if;
  select * into v_item from public.inventory_items where id=v_line.inventory_item_id for update;if not found then raise exception 'Inventory item not found';end if;
  update public.purchase_order_items set received_quantity=received_quantity+p_quantity where id=v_line.id;
  update public.inventory_items set on_hand=on_hand+p_quantity,unit_cost=v_line.unit_cost,location_id=p_location_id,location=v_loc.name where id=v_line.inventory_item_id;
  insert into public.inventory_location_stock(inventory_item_id,location_id,on_hand,reorder_point,max_stock,bin_code) values(v_line.inventory_item_id,p_location_id,p_quantity,v_item.reorder_point,v_item.max_stock,case when v_item.location_id=p_location_id then v_item.bin_code else null end) on conflict(inventory_item_id,location_id) do update set on_hand=public.inventory_location_stock.on_hand+excluded.on_hand,reorder_point=excluded.reorder_point,max_stock=excluded.max_stock,updated_at=now();
  insert into public.inventory_transactions(inventory_item_id,location_id,purchase_order_id,transaction_type,quantity,unit_cost,actor_user_id) values(v_line.inventory_item_id,p_location_id,v_po.id,'receive',p_quantity,v_line.unit_cost,v_user.id) returning id into v_tx;
  insert into public.supplier_cost_observations(inventory_item_id,supplier_id,supplier_sku,unit_cost,source,observed_at,recorded_by) values(v_line.inventory_item_id,v_po.supplier_id,v_item.supplier_sku,v_line.unit_cost,'purchase_order',now(),v_user.id);
  select case when not exists(select 1 from public.purchase_order_items li where li.purchase_order_id=v_po.id and li.received_quantity<li.quantity) then 'received' else 'partial' end into v_new_status;
  update public.purchase_orders set status=v_new_status,receive_location_id=p_location_id,received_at=case when v_new_status='received' then now() else received_at end where id=v_po.id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_user.id,'receive_purchase_order_line','purchase_order',v_po.id::text,jsonb_build_object('line_id',v_line.id,'received_quantity',v_line.received_quantity,'status',v_po.status,'item_on_hand',v_item.on_hand),jsonb_build_object('line_id',v_line.id,'received_quantity',v_line.received_quantity+p_quantity,'quantity_received_now',p_quantity,'status',v_new_status,'location_id',p_location_id,'item_on_hand',v_item.on_hand+p_quantity,'inventory_transaction_id',v_tx));return v_tx;
end$$;

create or replace function private.consume_inventory_for_job_impl(p_job_id uuid,p_inventory_item_id uuid,p_quantity numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user public.users%rowtype;v_item public.inventory_items%rowtype;v_job public.jobs%rowtype;v_tx uuid;v_usage uuid;v_location_id uuid;v_assigned_location_id uuid;v_location_qty numeric;
begin
  select * into v_user from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_user.id is null then raise exception 'Employee identity unavailable'; end if;
  if p_job_id is null or p_inventory_item_id is null or p_quantity is null or p_quantity<=0 then raise exception 'Valid job, item and quantity required';end if;
  select * into v_job from public.jobs where id=p_job_id for update;if not found then raise exception 'Job not found';end if;
  if v_job.technician_id is distinct from v_user.id and not (private.has_permission('manage_jobs') or private.has_permission('manage_dispatch')) then raise exception 'Field users can only update their assigned jobs'; end if;
  if v_job.status<>'on_site' then raise exception 'Job must be on site before recording materials';end if;
  select * into v_item from public.inventory_items where id=p_inventory_item_id for update;if not found then raise exception 'Inventory item not found';end if;if v_item.on_hand<p_quantity then raise exception 'Insufficient inventory';end if;
  select id into v_assigned_location_id from public.inventory_locations where assigned_user_id=v_user.id and active=true and location_type='truck' order by created_at limit 1;
  if v_assigned_location_id is not null then
    v_location_id:=v_assigned_location_id;
    select on_hand into v_location_qty from public.inventory_location_stock where inventory_item_id=p_inventory_item_id and location_id=v_location_id for update;
    if v_location_qty is null or v_location_qty<p_quantity then raise exception 'Insufficient inventory in assigned truck'; end if;
  elsif exists(select 1 from public.inventory_location_stock where inventory_item_id=p_inventory_item_id) then
    v_location_id:=v_item.location_id;
    if v_location_id is null then raise exception 'Inventory location required before field consumption'; end if;
    select on_hand into v_location_qty from public.inventory_location_stock where inventory_item_id=p_inventory_item_id and location_id=v_location_id for update;
    if v_location_qty is null or v_location_qty<p_quantity then raise exception 'Insufficient inventory at primary location'; end if;
  else v_location_id:=v_item.location_id; end if;
  update public.inventory_items set on_hand=on_hand-p_quantity where id=v_item.id;
  if v_location_qty is not null then update public.inventory_location_stock set on_hand=on_hand-p_quantity,updated_at=now() where inventory_item_id=v_item.id and location_id=v_location_id; end if;
  insert into public.material_usage(job_id,inventory_item_id,sku,description,quantity,unit_cost,source) values(p_job_id,v_item.id,v_item.sku,v_item.description,p_quantity,v_item.unit_cost,'inventory') returning id into v_usage;
  insert into public.inventory_transactions(inventory_item_id,location_id,job_id,transaction_type,quantity,unit_cost,actor_user_id) values(v_item.id,v_location_id,p_job_id,'job_use',-p_quantity,v_item.unit_cost,v_user.id) returning id into v_tx;
  update public.jobs set material_cost=coalesce((select sum(quantity*unit_cost) from public.material_usage where job_id=p_job_id),0) where id=p_job_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_user.id,'consume_inventory_for_job','job',p_job_id::text,jsonb_build_object('inventory_item_id',v_item.id,'on_hand',v_item.on_hand,'location_id',v_location_id),jsonb_build_object('inventory_item_id',v_item.id,'quantity',p_quantity,'remaining_on_hand',v_item.on_hand-p_quantity,'location_id',v_location_id,'material_usage_id',v_usage,'inventory_transaction_id',v_tx));return v_tx;
end$$;