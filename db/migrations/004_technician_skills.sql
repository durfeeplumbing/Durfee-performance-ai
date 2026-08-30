create table if not exists public.technician_skills (
 id uuid primary key default gen_random_uuid(),
 technician_id uuid not null references public.users(id) on delete cascade,
 skill text not null,
 proficiency integer not null default 50 check (proficiency between 0 and 100),
 certified boolean not null default false,
 certification_name text,
 certification_expires_on date,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(technician_id,skill)
);
create index if not exists technician_skills_technician_idx on public.technician_skills(technician_id);
alter table public.technician_skills enable row level security;
create policy "authenticated read technician skills" on public.technician_skills for select to authenticated using (true);
create policy "owner manager manage technician skills" on public.technician_skills for all to authenticated using (private.current_employee_role() in ('owner','manager')) with check (private.current_employee_role() in ('owner','manager'));
