create table if not exists public.customer_followups (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.customers(id) on delete cascade,
 equipment_id uuid references public.customer_equipment(id) on delete set null,
 csr_user_id uuid not null references public.users(id),
 channel text not null check(channel in ('phone','sms','email','other')),
 outcome text not null check(outcome in ('no_answer','left_message','spoke_not_ready','callback','booked','declined','other')),
 notes text,
 follow_up_at timestamptz,
 booked_job_id uuid references public.jobs(id) on delete set null,
 created_at timestamptz not null default now()
);
create index if not exists customer_followups_customer_idx on public.customer_followups(customer_id,created_at desc);
create index if not exists customer_followups_csr_idx on public.customer_followups(csr_user_id,created_at desc);
create index if not exists customer_followups_due_idx on public.customer_followups(follow_up_at) where follow_up_at is not null;
alter table public.customer_followups enable row level security;
create policy "staff read customer followups" on public.customer_followups for select to authenticated using (private.current_employee_role() in ('owner','manager','csr_dispatch'));
create policy "staff create customer followups" on public.customer_followups for insert to authenticated with check (csr_user_id=(select id from public.users where auth_user_id=auth.uid() and active=true limit 1) and private.current_employee_role() in ('owner','manager','csr_dispatch'));
create policy "staff update own customer followups" on public.customer_followups for update to authenticated using (private.current_employee_role() in ('owner','manager') or csr_user_id=(select id from public.users where auth_user_id=auth.uid() and active=true limit 1)) with check (private.current_employee_role() in ('owner','manager') or csr_user_id=(select id from public.users where auth_user_id=auth.uid() and active=true limit 1));
