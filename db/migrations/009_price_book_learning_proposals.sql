create table if not exists public.price_book_learning_proposals (
 id uuid primary key default gen_random_uuid(),
 price_book_item_id uuid not null references public.price_book_items(id) on delete cascade,
 service_type text,
 sample_size integer not null default 0 check (sample_size>=0),
 current_labor_hours numeric not null default 0,
 proposed_labor_hours numeric not null default 0,
 current_target_gp numeric not null default 50,
 proposed_target_gp numeric not null default 50,
 evidence jsonb not null default '{}'::jsonb,
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references public.users(id)
);
create index if not exists price_book_learning_proposals_status_idx on public.price_book_learning_proposals(status,created_at desc);
alter table public.price_book_learning_proposals enable row level security;
create policy "owner manager read learning proposals" on public.price_book_learning_proposals for select to authenticated using (private.current_employee_role() in ('owner','manager'));
create policy "owner manage learning proposals" on public.price_book_learning_proposals for insert to authenticated with check (private.current_employee_role()='owner');
create policy "owner update learning proposals" on public.price_book_learning_proposals for update to authenticated using (private.current_employee_role()='owner') with check (private.current_employee_role()='owner');
