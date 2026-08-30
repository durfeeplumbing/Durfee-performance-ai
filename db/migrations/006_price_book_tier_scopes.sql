create table if not exists public.price_book_tiers (
 id uuid primary key default gen_random_uuid(),
 price_book_item_id uuid not null references public.price_book_items(id) on delete cascade,
 tier text not null check (tier in ('Good','Better','Best')),
 name text not null,
 description text,
 material_cost numeric not null default 0 check (material_cost >= 0),
 labor_hours numeric not null default 0 check (labor_hours >= 0),
 overhead numeric not null default 0 check (overhead >= 0),
 target_gp numeric not null default 50 check (target_gp >= 0 and target_gp < 100),
 active boolean not null default true,
 updated_at timestamptz not null default now(),
 unique(price_book_item_id,tier)
);
alter table public.price_book_tiers enable row level security;
create policy "authenticated read price book tiers" on public.price_book_tiers for select to authenticated using (true);
create policy "owner manage price book tiers" on public.price_book_tiers for all to authenticated using (private.current_employee_role()='owner') with check (private.current_employee_role()='owner');
create index if not exists price_book_tiers_item_idx on public.price_book_tiers(price_book_item_id);
