create table if not exists public.migration_readiness_checks (
  module_key text primary key,
  module_name text not null,
  category text not null,
  criticality text not null check (criticality in ('critical','high','medium','low')),
  status text not null default 'not_started' check (status in ('not_started','testing','parallel','ready','blocked')),
  servicetitan_dependency boolean not null default true,
  tests_passed integer not null default 0 check (tests_passed >= 0),
  tests_failed integer not null default 0 check (tests_failed >= 0),
  open_mismatches integer not null default 0 check (open_mismatches >= 0),
  notes text,
  target_date date,
  updated_at timestamptz not null default now()
);

alter table public.migration_readiness_checks enable row level security;

grant select, update on public.migration_readiness_checks to authenticated;

create policy "owners can read migration readiness"
on public.migration_readiness_checks
for select
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.active = true
      and u.role = 'owner'
  )
);

create policy "owners can update migration readiness"
on public.migration_readiness_checks
for update
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.active = true
      and u.role = 'owner'
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.auth_user_id = (select auth.uid())
      and u.active = true
      and u.role = 'owner'
  )
);

insert into public.migration_readiness_checks
  (module_key,module_name,category,criticality,status,servicetitan_dependency,target_date)
values
  ('customer_crm','Customer CRM & history','Operations','critical','testing',true,'2027-03-01'),
  ('booking','CSR booking & call intake','Operations','critical','testing',true,'2027-03-01'),
  ('dispatch','Scheduling & dispatch','Operations','critical','testing',true,'2027-03-15'),
  ('field_app','Technician field workflow','Field','critical','testing',true,'2027-03-15'),
  ('estimates','Estimates & approvals','Sales','critical','parallel',true,'2027-03-31'),
  ('pricebook','Price book & GP guardrails','Sales','critical','parallel',false,'2027-03-31'),
  ('invoicing','Invoicing & job closeout','Finance','critical','testing',true,'2027-04-15'),
  ('payments','Payments & reconciliation','Finance','critical','not_started',true,'2027-04-15'),
  ('memberships','Memberships & recurring service','Operations','high','testing',true,'2027-04-30'),
  ('communications','Phone, SMS & notifications','Communications','critical','testing',true,'2027-04-30'),
  ('accounting','AP, AR & accounting handoff','Finance','critical','testing',true,'2027-05-01'),
  ('payroll','Payroll inputs & technician time','Finance','high','not_started',true,'2027-05-01'),
  ('reporting','Owner reporting & KPI accuracy','Management','high','parallel',true,'2027-05-15'),
  ('permissions','Roles, permissions & audit trail','Security','critical','testing',false,'2027-05-15'),
  ('documents','Photos, documents & vendor invoices','Field','high','testing',false,'2027-05-15'),
  ('backup_recovery','Backup, restore & incident recovery','Reliability','critical','not_started',false,'2027-05-31'),
  ('monitoring','Uptime, errors & alerting','Reliability','critical','testing',false,'2027-05-31'),
  ('st_exit','ServiceTitan final export & archive','Migration','critical','not_started',true,'2027-06-15')
on conflict (module_key) do nothing;

create or replace function public.touch_migration_readiness_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists migration_readiness_touch on public.migration_readiness_checks;
create trigger migration_readiness_touch
before update on public.migration_readiness_checks
for each row execute function public.touch_migration_readiness_updated_at();
