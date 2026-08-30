create or replace function public.create_purchase_order(p_supplier_id uuid,p_customer_id uuid default null,p_notes text default null,p_expected_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_user public.users%rowtype;v_supplier public.suppliers%rowtype;v_customer public.customers%rowtype;v_id uuid;v_date text;v_customer_code text;v_seq integer;v_po text;begin
select * into v_user from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_user.id is null or v_user.role not in ('owner','manager','accounting') then raise exception 'Not authorized';end if;
if p_supplier_id is null then raise exception 'Supplier required';end if;if length(coalesce(p_notes,''))>3000 then raise exception 'Notes too long';end if;if p_expected_at is not null and p_expected_at<now()-interval '1 day' then raise exception 'Expected date cannot be in the past';end if;
select * into v_supplier from public.suppliers where id=p_supplier_id and active=true;if not found then raise exception 'Supplier not found';end if;
if p_customer_id is not null then select * into v_customer from public.customers where id=p_customer_id;if not found then raise exception 'Customer not found';end if;v_customer_code:=v_customer.customer_code;else v_customer_code:='STOCK';end if;
v_date:=to_char(current_date,'YYMMDD');perform pg_advisory_xact_lock(hashtextextended(v_supplier.vendor_code||':'||v_date||':'||coalesce(v_customer_code,'STOCK'),0));
select coalesce(max(nullif(regexp_replace(po_number,'.*-([0-9]{2})$','\1'),'')::int),0)+1 into v_seq from public.purchase_orders where supplier_id=p_supplier_id and coalesce(customer_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(p_customer_id,'00000000-0000-0000-0000-000000000000'::uuid) and created_at::date=current_date;
v_po:=upper(v_supplier.vendor_code)||'-'||v_date||'-'||coalesce(v_customer_code,'STOCK')||'-'||lpad(v_seq::text,2,'0');
insert into public.purchase_orders(supplier_id,customer_id,po_number,status,ordered_by,expected_at,notes) values(p_supplier_id,p_customer_id,v_po,'draft',v_user.id,p_expected_at,nullif(btrim(p_notes),'')) returning id into v_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_user.id,'create_purchase_order','purchase_order',v_id::text,jsonb_build_object('po_number',v_po,'supplier_id',p_supplier_id,'customer_id',p_customer_id,'expected_at',p_expected_at));return v_id;end;$$;

create or replace function public.finalize_purchase_order_document_atomic(p_purchase_order_id uuid,p_storage_path text,p_file_name text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_user public.users%rowtype;v_po public.purchase_orders%rowtype;v_id uuid;begin
select * into v_user from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_user.id is null or v_user.role not in ('owner','manager','accounting') then raise exception 'Not authorized';end if;
if p_purchase_order_id is null or nullif(btrim(coalesce(p_storage_path,'')),'') is null then raise exception 'Purchase order and storage path required';end if;if length(coalesce(p_file_name,''))>500 then raise exception 'File name too long';end if;
select * into v_po from public.purchase_orders where id=p_purchase_order_id for update;if not found then raise exception 'Purchase order not found';end if;if v_po.status='cancelled' then raise exception 'Cannot attach invoice to cancelled purchase order';end if;
insert into public.purchase_order_documents(purchase_order_id,document_type,storage_path,file_name,uploaded_by) values(p_purchase_order_id,'vendor_invoice',btrim(p_storage_path),nullif(btrim(p_file_name),''),v_user.id) returning id into v_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_user.id,'upload_vendor_invoice','purchase_order',p_purchase_order_id::text,jsonb_build_object('document_id',v_id,'file_name',nullif(btrim(p_file_name),''),'storage_path',btrim(p_storage_path)));return v_id;end;$$;

create or replace function public.receive_purchase_order_line(p_line_id uuid,p_quantity numeric,p_location_id uuid)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_user public.users%rowtype;v_line public.purchase_order_items%rowtype;v_po public.purchase_orders%rowtype;v_loc public.inventory_locations%rowtype;v_item public.inventory_items%rowtype;v_tx uuid;v_new_status text;begin
select * into v_user from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_user.id is null or v_user.role not in ('owner','manager','accounting') then raise exception 'Not authorized';end if;
if p_quantity is null or p_quantity<=0 or p_line_id is null or p_location_id is null then raise exception 'Valid line, quantity and location required';end if;
select * into v_loc from public.inventory_locations where id=p_location_id and active=true;if not found then raise exception 'Receiving location not found or inactive';end if;
select * into v_line from public.purchase_order_items where id=p_line_id for update;if not found or v_line.inventory_item_id is null then raise exception 'Invalid PO line';end if;if v_line.received_quantity+p_quantity>v_line.quantity then raise exception 'Cannot receive more than ordered';end if;
select * into v_po from public.purchase_orders where id=v_line.purchase_order_id for update;if not found then raise exception 'Purchase order not found';end if;if v_po.status not in ('draft','submitted','partial') then raise exception 'Purchase order cannot be received in its current state';end if;
if not exists(select 1 from public.purchase_order_documents d where d.purchase_order_id=v_po.id and d.document_type='vendor_invoice') then raise exception 'Vendor invoice photo or PDF is required before receiving material';end if;
select * into v_item from public.inventory_items where id=v_line.inventory_item_id for update;if not found then raise exception 'Inventory item not found';end if;
update public.purchase_order_items set received_quantity=received_quantity+p_quantity where id=v_line.id;
update public.inventory_items set on_hand=on_hand+p_quantity,unit_cost=v_line.unit_cost,location_id=p_location_id,location=v_loc.name where id=v_line.inventory_item_id;
insert into public.inventory_transactions(inventory_item_id,location_id,purchase_order_id,transaction_type,quantity,unit_cost,actor_user_id) values(v_line.inventory_item_id,p_location_id,v_po.id,'receive',p_quantity,v_line.unit_cost,v_user.id) returning id into v_tx;
select case when not exists(select 1 from public.purchase_order_items li where li.purchase_order_id=v_po.id and li.received_quantity<li.quantity) then 'received' else 'partial' end into v_new_status;
update public.purchase_orders set status=v_new_status,receive_location_id=p_location_id,received_at=case when v_new_status='received' then now() else received_at end where id=v_po.id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_user.id,'receive_purchase_order_line','purchase_order',v_po.id::text,jsonb_build_object('line_id',v_line.id,'received_quantity',v_line.received_quantity,'status',v_po.status,'item_on_hand',v_item.on_hand),jsonb_build_object('line_id',v_line.id,'received_quantity',v_line.received_quantity+p_quantity,'quantity_received_now',p_quantity,'status',v_new_status,'location_id',p_location_id,'item_on_hand',v_item.on_hand+p_quantity,'inventory_transaction_id',v_tx));return v_tx;end;$$;

revoke all on function public.create_purchase_order(uuid,uuid,text,timestamptz) from public;grant execute on function public.create_purchase_order(uuid,uuid,text,timestamptz) to authenticated;
revoke all on function public.finalize_purchase_order_document_atomic(uuid,text,text) from public;grant execute on function public.finalize_purchase_order_document_atomic(uuid,text,text) to authenticated;
revoke all on function public.receive_purchase_order_line(uuid,numeric,uuid) from public;grant execute on function public.receive_purchase_order_line(uuid,numeric,uuid) to authenticated;