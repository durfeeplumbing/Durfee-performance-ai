create or replace function public.consume_inventory_for_job(p_job_id uuid,p_inventory_item_id uuid,p_quantity numeric)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_user public.users%rowtype;v_item public.inventory_items%rowtype;v_job public.jobs%rowtype;v_tx uuid;v_usage uuid;begin
select * into v_user from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_user.id is null or v_user.role not in ('owner','manager','technician') then raise exception 'Not authorized';end if;
if p_job_id is null or p_inventory_item_id is null or p_quantity is null or p_quantity<=0 then raise exception 'Valid job, item and quantity required';end if;
select * into v_job from public.jobs where id=p_job_id for update;if not found then raise exception 'Job not found';end if;
if v_user.role='technician' and v_job.technician_id is distinct from v_user.id then raise exception 'Technicians can only update assigned jobs';end if;
if v_job.status<>'on_site' then raise exception 'Job must be on site before recording materials';end if;
select * into v_item from public.inventory_items where id=p_inventory_item_id for update;if not found then raise exception 'Inventory item not found';end if;if v_item.on_hand<p_quantity then raise exception 'Insufficient inventory';end if;
update public.inventory_items set on_hand=on_hand-p_quantity where id=v_item.id;
insert into public.material_usage(job_id,inventory_item_id,sku,description,quantity,unit_cost,source) values(p_job_id,v_item.id,v_item.sku,v_item.description,p_quantity,v_item.unit_cost,'inventory') returning id into v_usage;
insert into public.inventory_transactions(inventory_item_id,location_id,job_id,transaction_type,quantity,unit_cost,actor_user_id) values(v_item.id,v_item.location_id,p_job_id,'job_use',-p_quantity,v_item.unit_cost,v_user.id) returning id into v_tx;
update public.jobs set material_cost=coalesce((select sum(quantity*unit_cost) from public.material_usage where job_id=p_job_id),0) where id=p_job_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_user.id,'consume_inventory_for_job','job',p_job_id::text,jsonb_build_object('inventory_item_id',v_item.id,'on_hand',v_item.on_hand),jsonb_build_object('inventory_item_id',v_item.id,'quantity',p_quantity,'remaining_on_hand',v_item.on_hand-p_quantity,'material_usage_id',v_usage,'inventory_transaction_id',v_tx));return v_tx;end;$$;
revoke all on function public.consume_inventory_for_job(uuid,uuid,numeric) from public;grant execute on function public.consume_inventory_for_job(uuid,uuid,numeric) to authenticated;