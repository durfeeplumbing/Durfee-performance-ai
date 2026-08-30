create table if not exists public.customer_equipment (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.customers(id) on delete cascade,
 installed_job_id uuid references public.jobs(id) on delete set null,
 equipment_type text not null,
 manufacturer text,
 model_number text,
 serial_number text,
 location text,
 installed_on date,
 warranty_expires_on date,
 last_service_on date,
 next_maintenance_on date,
 status text not null default 'active' check(status in ('active','inactive','replaced')),
 notes text,
 created_by uuid references public.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists customer_equipment_customer_idx on public.customer_equipment(customer_id,status);
create index if not exists customer_equipment_maintenance_idx on public.customer_equipment(next_maintenance_on) where status='active';
alter table public.customer_equipment enable row level security;
create policy "authenticated read customer equipment" on public.customer_equipment for select to authenticated using (private.current_employee_role() in ('owner','manager','csr_dispatch','technician','accounting'));
create policy "field staff add customer equipment" on public.customer_equipment for insert to authenticated with check (created_by=(select id from public.users where auth_user_id=auth.uid() and active=true limit 1) and private.current_employee_role() in ('owner','manager','csr_dispatch','technician'));
create policy "managers update customer equipment" on public.customer_equipment for update to authenticated using (private.current_employee_role() in ('owner','manager','csr_dispatch','technician')) with check (private.current_employee_role() in ('owner','manager','csr_dispatch','technician'));
