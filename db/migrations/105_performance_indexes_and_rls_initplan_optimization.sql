create index if not exists jobs_customer_id_idx on public.jobs(customer_id);
create index if not exists payments_invoice_id_idx on public.payments(invoice_id);
create index if not exists estimate_options_estimate_id_idx on public.estimate_options(estimate_id);
create index if not exists time_entries_technician_id_idx on public.time_entries(technician_id);

create index if not exists accounts_payable_customer_id_idx on public.accounts_payable(customer_id);
create index if not exists accounts_payable_supplier_id_idx on public.accounts_payable(supplier_id);
create index if not exists accounts_payable_posted_by_idx on public.accounts_payable(posted_by);

create index if not exists accounts_payable_entries_purchase_order_id_idx on public.accounts_payable_entries(purchase_order_id);
create index if not exists accounts_payable_entries_supplier_id_idx on public.accounts_payable_entries(supplier_id);
create index if not exists accounts_payable_entries_customer_id_idx on public.accounts_payable_entries(customer_id);
create index if not exists accounts_payable_entries_posted_by_idx on public.accounts_payable_entries(posted_by);

create index if not exists ap_payments_accounts_payable_id_idx on public.ap_payments(accounts_payable_id);
create index if not exists ap_payments_accounts_payable_entry_id_idx on public.ap_payments(accounts_payable_entry_id);
create index if not exists ap_payments_recorded_by_idx on public.ap_payments(recorded_by);
create index if not exists ap_payments_reversed_by_idx on public.ap_payments(reversed_by);

create index if not exists purchase_orders_supplier_id_idx on public.purchase_orders(supplier_id);
create index if not exists purchase_orders_customer_id_idx on public.purchase_orders(customer_id);
create index if not exists purchase_orders_ordered_by_idx on public.purchase_orders(ordered_by);
create index if not exists purchase_orders_receive_location_id_idx on public.purchase_orders(receive_location_id);
create index if not exists purchase_order_items_purchase_order_id_idx on public.purchase_order_items(purchase_order_id);
create index if not exists purchase_order_items_inventory_item_id_idx on public.purchase_order_items(inventory_item_id);

create index if not exists inventory_items_location_id_idx on public.inventory_items(location_id);
create index if not exists inventory_items_supplier_id_idx on public.inventory_items(supplier_id);
create index if not exists inventory_transactions_inventory_item_id_idx on public.inventory_transactions(inventory_item_id);
create index if not exists inventory_transactions_location_id_idx on public.inventory_transactions(location_id);
create index if not exists inventory_transactions_job_id_idx on public.inventory_transactions(job_id);
create index if not exists inventory_transactions_purchase_order_id_idx on public.inventory_transactions(purchase_order_id);
create index if not exists inventory_transactions_actor_user_id_idx on public.inventory_transactions(actor_user_id);

create index if not exists job_callbacks_created_by_idx on public.job_callbacks(created_by);
create index if not exists job_callbacks_reviewed_by_idx on public.job_callbacks(reviewed_by);
create index if not exists job_cost_allocations_job_id_idx on public.job_cost_allocations(job_id);
create index if not exists job_cost_allocations_created_by_idx on public.job_cost_allocations(created_by);
create index if not exists job_cost_allocations_reversed_by_idx on public.job_cost_allocations(reversed_by);

drop policy if exists "owner or self read user permission overrides" on public.user_permission_overrides;
create policy "owner or self read user permission overrides"
on public.user_permission_overrides
for select
to authenticated
using (
  private.current_employee_role() = 'owner'
  or user_id = (
    select u.id
    from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.active = true
    limit 1
  )
);

drop policy if exists "purchasing add documents" on public.purchase_order_documents;
create policy "purchasing add documents"
on public.purchase_order_documents
for insert
to authenticated
with check (
  private.current_employee_role() = any (array['owner'::text,'manager'::text,'accounting'::text])
  and private.has_permission('manage_purchasing'::text)
  and uploaded_by = (
    select u.id
    from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.active = true
    limit 1
  )
);

drop policy if exists "zero invoice approval read own or managers" on public.zero_invoice_closeout_approvals;
create policy "zero invoice approval read own or managers"
on public.zero_invoice_closeout_approvals
for select
to authenticated
using (
  exists (
    select 1
    from public.jobs j
    join public.users u
      on u.auth_user_id = (select auth.uid())
     and u.active = true
    where j.id = zero_invoice_closeout_approvals.job_id
      and (
        j.technician_id = u.id
        or private.has_permission('manage_jobs'::text)
        or private.has_permission('manage_billing'::text)
      )
  )
);
