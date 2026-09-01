alter function public.create_purchase_order_impl(uuid,uuid,text,timestamptz) set schema private;
alter function public.receive_purchase_order_line_impl(uuid,numeric,uuid) set schema private;
alter function public.finalize_purchase_order_document_atomic_impl(uuid,text,text) set schema private;
alter function public.create_inventory_item_atomic_impl(text,text,text,numeric,numeric,numeric) set schema private;
alter function public.update_inventory_item_atomic_impl(uuid,numeric,numeric,numeric,numeric,numeric,numeric) set schema private;
alter function public.review_price_book_learning_proposal_impl(uuid,text) set schema private;

grant execute on function private.create_purchase_order_impl(uuid,uuid,text,timestamptz) to authenticated;
grant execute on function private.receive_purchase_order_line_impl(uuid,numeric,uuid) to authenticated;
grant execute on function private.finalize_purchase_order_document_atomic_impl(uuid,text,text) to authenticated;
grant execute on function private.create_inventory_item_atomic_impl(text,text,text,numeric,numeric,numeric) to authenticated;
grant execute on function private.update_inventory_item_atomic_impl(uuid,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;
grant execute on function private.review_price_book_learning_proposal_impl(uuid,text) to authenticated;

create or replace function public.create_purchase_order(p_supplier_id uuid,p_customer_id uuid,p_notes text,p_expected_at timestamptz)
returns uuid language plpgsql security invoker set search_path='' as $$
begin if not private.has_permission('manage_purchasing') then raise exception 'Permission denied'; end if; return private.create_purchase_order_impl(p_supplier_id,p_customer_id,p_notes,p_expected_at); end$$;
create or replace function public.receive_purchase_order_line(p_line_id uuid,p_quantity numeric,p_location_id uuid)
returns uuid language plpgsql security invoker set search_path='' as $$
begin if not private.has_permission('manage_purchasing') then raise exception 'Permission denied'; end if; return private.receive_purchase_order_line_impl(p_line_id,p_quantity,p_location_id); end$$;
create or replace function public.finalize_purchase_order_document_atomic(p_purchase_order_id uuid,p_storage_path text,p_file_name text)
returns uuid language plpgsql security invoker set search_path='' as $$
begin if not private.has_permission('manage_purchasing') then raise exception 'Permission denied'; end if; return private.finalize_purchase_order_document_atomic_impl(p_purchase_order_id,p_storage_path,p_file_name); end$$;
create or replace function public.create_inventory_item_atomic(p_sku text,p_description text,p_location text,p_on_hand numeric,p_reorder_point numeric,p_unit_cost numeric)
returns uuid language plpgsql security invoker set search_path='' as $$
begin if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if; return private.create_inventory_item_atomic_impl(p_sku,p_description,p_location,p_on_hand,p_reorder_point,p_unit_cost); end$$;
create or replace function public.update_inventory_item_atomic(p_id uuid,p_expected_on_hand numeric,p_expected_reorder_point numeric,p_expected_unit_cost numeric,p_on_hand numeric,p_reorder_point numeric,p_unit_cost numeric)
returns uuid language plpgsql security invoker set search_path='' as $$
begin if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if; return private.update_inventory_item_atomic_impl(p_id,p_expected_on_hand,p_expected_reorder_point,p_expected_unit_cost,p_on_hand,p_reorder_point,p_unit_cost); end$$;
create or replace function public.review_price_book_learning_proposal(p_proposal_id uuid,p_decision text)
returns void language plpgsql security invoker set search_path='' as $$
begin if not private.has_permission('manage_pricebook') then raise exception 'Permission denied'; end if; perform private.review_price_book_learning_proposal_impl(p_proposal_id,p_decision); end$$;

revoke all on function public.create_purchase_order(uuid,uuid,text,timestamptz) from public,anon;
revoke all on function public.receive_purchase_order_line(uuid,numeric,uuid) from public,anon;
revoke all on function public.finalize_purchase_order_document_atomic(uuid,text,text) from public,anon;
revoke all on function public.create_inventory_item_atomic(text,text,text,numeric,numeric,numeric) from public,anon;
revoke all on function public.update_inventory_item_atomic(uuid,numeric,numeric,numeric,numeric,numeric,numeric) from public,anon;
revoke all on function public.review_price_book_learning_proposal(uuid,text) from public,anon;
grant execute on function public.create_purchase_order(uuid,uuid,text,timestamptz) to authenticated;
grant execute on function public.receive_purchase_order_line(uuid,numeric,uuid) to authenticated;
grant execute on function public.finalize_purchase_order_document_atomic(uuid,text,text) to authenticated;
grant execute on function public.create_inventory_item_atomic(text,text,text,numeric,numeric,numeric) to authenticated;
grant execute on function public.update_inventory_item_atomic(uuid,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;
grant execute on function public.review_price_book_learning_proposal(uuid,text) to authenticated;
