-- Remaining direct-write areas are permission aware. These tables support workflows
-- that still use normal table mutations for analysis/admin metadata.

drop policy if exists "dispatch manage route recommendations" on public.dispatch_route_recommendations;
create policy "dispatch manage route recommendations" on public.dispatch_route_recommendations
for all to authenticated
using (private.current_employee_role() in ('owner','manager','csr_dispatch') and private.has_permission('manage_dispatch'))
with check (private.current_employee_role() in ('owner','manager','csr_dispatch') and private.has_permission('manage_dispatch'));

drop policy if exists "managers manage inventory locations" on public.inventory_locations;
create policy "managers manage inventory locations" on public.inventory_locations
for all to authenticated
using (private.current_employee_role() in ('owner','manager') and private.has_permission('manage_inventory'))
with check (private.current_employee_role() in ('owner','manager') and private.has_permission('manage_inventory'));

drop policy if exists "managers manage purchase order items" on public.purchase_order_items;
create policy "purchasing manage purchase order items" on public.purchase_order_items
for all to authenticated
using (private.current_employee_role() in ('owner','manager','accounting') and private.has_permission('manage_purchasing'))
with check (private.current_employee_role() in ('owner','manager','accounting') and private.has_permission('manage_purchasing'));

drop policy if exists "managers manage purchase orders" on public.purchase_orders;
create policy "purchasing manage purchase orders" on public.purchase_orders
for all to authenticated
using (private.current_employee_role() in ('owner','manager','accounting') and private.has_permission('manage_purchasing'))
with check (private.current_employee_role() in ('owner','manager','accounting') and private.has_permission('manage_purchasing'));

drop policy if exists "managers manage suppliers" on public.suppliers;
create policy "purchasing manage suppliers" on public.suppliers
for all to authenticated
using (private.current_employee_role() in ('owner','manager') and private.has_permission('manage_purchasing'))
with check (private.current_employee_role() in ('owner','manager') and private.has_permission('manage_purchasing'));

drop policy if exists "purchasing staff add documents" on public.purchase_order_documents;
create policy "purchasing add documents" on public.purchase_order_documents
for insert to authenticated
with check (
  private.current_employee_role() in ('owner','manager','accounting')
  and private.has_permission('manage_purchasing')
  and uploaded_by=(select id from public.users where auth_user_id=auth.uid() and active=true limit 1)
);
create policy "purchasing update documents" on public.purchase_order_documents
for update to authenticated
using (private.current_employee_role() in ('owner','manager','accounting') and (private.has_permission('manage_purchasing') or private.has_permission('manage_accounting')))
with check (private.current_employee_role() in ('owner','manager','accounting') and (private.has_permission('manage_purchasing') or private.has_permission('manage_accounting')));

drop policy if exists "finance manage vendor bill drafts" on public.vendor_bill_drafts;
create policy "authorized manage vendor bill drafts" on public.vendor_bill_drafts
for all to authenticated
using (private.current_employee_role() in ('owner','manager','accounting') and (private.has_permission('manage_purchasing') or private.has_permission('manage_accounting')))
with check (private.current_employee_role() in ('owner','manager','accounting') and (private.has_permission('manage_purchasing') or private.has_permission('manage_accounting')));