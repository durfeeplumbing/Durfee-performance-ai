alter table public.jobs
  add column if not exists created_by uuid references public.users(id) on delete set null;
create index if not exists jobs_created_by_idx on public.jobs(created_by);

drop policy if exists invoice_finance_insert on public.invoices;
create policy invoice_finance_insert on public.invoices
  for insert to authenticated
  with check (private.current_employee_role() in ('owner','manager','accounting'));

drop policy if exists invoice_finance_update on public.invoices;
create policy invoice_finance_update on public.invoices
  for update to authenticated
  using (private.current_employee_role() in ('owner','manager','accounting'))
  with check (private.current_employee_role() in ('owner','manager','accounting'));

drop policy if exists payment_finance_insert on public.payments;
create policy payment_finance_insert on public.payments
  for insert to authenticated
  with check (private.current_employee_role() in ('owner','manager','accounting'));

drop policy if exists payment_finance_update on public.payments;
create policy payment_finance_update on public.payments
  for update to authenticated
  using (private.current_employee_role() in ('owner','manager','accounting'))
  with check (private.current_employee_role() in ('owner','manager','accounting'));
