create or replace function public.create_inventory_item_atomic(p_sku text,p_description text,p_location text,p_on_hand numeric,p_reorder_point numeric,p_unit_cost numeric)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_role text;v_actor uuid;v_id uuid;begin
v_role:=private.current_employee_role();if v_role not in ('owner','manager') then raise exception 'Not authorized';end if;
select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_actor is null then raise exception 'Employee identity unavailable';end if;
if nullif(btrim(coalesce(p_sku,'')),'') is null or nullif(btrim(coalesce(p_description,'')),'') is null or nullif(btrim(coalesce(p_location,'')),'') is null then raise exception 'SKU, description and location required';end if;
if coalesce(p_on_hand,-1)<0 or coalesce(p_reorder_point,-1)<0 or coalesce(p_unit_cost,-1)<0 then raise exception 'Inventory values cannot be negative';end if;
insert into public.inventory_items(sku,description,on_hand,reorder_point,unit_cost,location) values(btrim(p_sku),btrim(p_description),p_on_hand,p_reorder_point,p_unit_cost,btrim(p_location)) returning id into v_id;
if p_on_hand<>0 then insert into public.inventory_transactions(inventory_item_id,location_id,transaction_type,quantity,unit_cost,actor_user_id) select v_id,location_id,'adjustment',p_on_hand,p_unit_cost,v_actor from public.inventory_items where id=v_id;end if;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'create_inventory_item','inventory_item',v_id::text,jsonb_build_object('sku',btrim(p_sku),'description',btrim(p_description),'location',btrim(p_location),'on_hand',p_on_hand,'reorder_point',p_reorder_point,'unit_cost',p_unit_cost));return v_id;end;$$;
create or replace function public.update_inventory_item_atomic(p_id uuid,p_expected_on_hand numeric,p_expected_reorder_point numeric,p_expected_unit_cost numeric,p_on_hand numeric,p_reorder_point numeric,p_unit_cost numeric)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_role text;v_actor uuid;v_item public.inventory_items%rowtype;v_delta numeric;begin
v_role:=private.current_employee_role();if v_role not in ('owner','manager') then raise exception 'Not authorized';end if;
select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_actor is null then raise exception 'Employee identity unavailable';end if;
if p_id is null or coalesce(p_on_hand,-1)<0 or coalesce(p_reorder_point,-1)<0 or coalesce(p_unit_cost,-1)<0 then raise exception 'Invalid inventory values';end if;
select * into v_item from public.inventory_items where id=p_id for update;if not found then raise exception 'Inventory item not found';end if;
if v_item.on_hand is distinct from p_expected_on_hand or v_item.reorder_point is distinct from p_expected_reorder_point or v_item.unit_cost is distinct from p_expected_unit_cost then raise exception 'Inventory item changed; refresh before saving';end if;
v_delta:=p_on_hand-v_item.on_hand;
update public.inventory_items set on_hand=p_on_hand,reorder_point=p_reorder_point,unit_cost=p_unit_cost where id=p_id;
if v_delta<>0 then insert into public.inventory_transactions(inventory_item_id,location_id,transaction_type,quantity,unit_cost,actor_user_id) values(p_id,v_item.location_id,'adjustment',v_delta,p_unit_cost,v_actor);end if;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_actor,'update_inventory_item','inventory_item',p_id::text,jsonb_build_object('on_hand',v_item.on_hand,'reorder_point',v_item.reorder_point,'unit_cost',v_item.unit_cost),jsonb_build_object('on_hand',p_on_hand,'reorder_point',p_reorder_point,'unit_cost',p_unit_cost));return p_id;end;$$;
revoke all on function public.create_inventory_item_atomic(text,text,text,numeric,numeric,numeric) from public;grant execute on function public.create_inventory_item_atomic(text,text,text,numeric,numeric,numeric) to authenticated;
revoke all on function public.update_inventory_item_atomic(uuid,numeric,numeric,numeric,numeric,numeric,numeric) from public;grant execute on function public.update_inventory_item_atomic(uuid,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;