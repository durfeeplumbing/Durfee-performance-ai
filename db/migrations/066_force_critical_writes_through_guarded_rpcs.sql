-- Critical workflows are mutated only through hardened SECURITY DEFINER RPCs.
-- Removing direct table-write policies prevents signed-in clients from bypassing
-- state, GP, pricing, assignment, audit, and permission checks.
drop policy if exists "customer_write_ops" on public.customers;
drop policy if exists "estimate_write_ops" on public.estimates;
drop policy if exists "estimate_option_write_ops" on public.estimate_options;
drop policy if exists "ops create estimate acceptance links" on public.estimate_acceptance_links;
drop policy if exists "ops update estimate acceptance links" on public.estimate_acceptance_links;
drop policy if exists "invoice_finance_insert" on public.invoices;
drop policy if exists "invoice_finance_update" on public.invoices;
drop policy if exists "payment_finance_insert" on public.payments;
drop policy if exists "payment_finance_update" on public.payments;
drop policy if exists "job_write_ops" on public.jobs;
drop policy if exists "job_update_assigned_tech" on public.jobs;
drop policy if exists "time_write_tech" on public.time_entries;
drop policy if exists "material_write_staff" on public.material_usage;
drop policy if exists "field staff add job notes" on public.job_notes;
drop policy if exists "field staff add job attachments" on public.job_attachments;
drop policy if exists "field staff add customer equipment" on public.customer_equipment;
drop policy if exists "managers update customer equipment" on public.customer_equipment;
drop policy if exists "owner manager manage technician skills" on public.technician_skills;
drop policy if exists "staff create customer followups" on public.customer_followups;
drop policy if exists "staff update own customer followups" on public.customer_followups;
drop policy if exists "owner manage pricing settings" on public.company_pricing_settings;
drop policy if exists "owner manage price book tiers" on public.price_book_tiers;
drop policy if exists "owner manage learning proposals" on public.price_book_learning_proposals;
drop policy if exists "owner update learning proposals" on public.price_book_learning_proposals;

-- Accounting writes are also RPC-only so reconciliation/overpayment/allocation guards cannot be bypassed.
drop policy if exists "finance manage ap entries" on public.accounts_payable_entries;
drop policy if exists "finance manage ap payments" on public.ap_payments;
drop policy if exists "finance manage allocations" on public.job_cost_allocations;

-- Legacy compatibility AP table is read/compatibility only; no direct staff writes.
drop policy if exists "finance manage ap" on public.accounts_payable;

-- Staging creation is now guarded by create_job_material_stage; direct changes are blocked.
drop policy if exists "office manage material staging" on public.job_material_staging;