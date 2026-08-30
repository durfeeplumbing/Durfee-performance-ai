create table if not exists public.company_pricing_settings (
 id boolean primary key default true check (id=true),
 labor_rate numeric not null default 325 check (labor_rate > 0),
 minimum_gp numeric not null default 50 check (minimum_gp >= 0 and minimum_gp < 100),
 default_overhead numeric not null default 0 check (default_overhead >= 0),
 membership_discount_pct numeric not null default 10 check (membership_discount_pct >= 0 and membership_discount_pct < 100),
 allow_owner_below_floor boolean not null default true,
 updated_at timestamptz not null default now(),
 updated_by uuid references public.users(id)
);
insert into public.company_pricing_settings(id) values (true) on conflict (id) do nothing;
alter table public.company_pricing_settings enable row level security;
create policy "authenticated read pricing settings" on public.company_pricing_settings for select to authenticated using (true);
create policy "owner manage pricing settings" on public.company_pricing_settings for update to authenticated using (private.current_employee_role()='owner') with check (private.current_employee_role()='owner');
