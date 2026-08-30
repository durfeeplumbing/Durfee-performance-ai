alter table public.jobs add column if not exists service_type text;
alter table public.jobs add column if not exists service_summary text;
alter table public.jobs add constraint jobs_service_type_check check (service_type is null or service_type in ('Plumbing Service','Drain & Sewer','Water Heaters','Tankless','Boilers','Furnaces','Heat Pumps','Ductless Mini-Splits','Central AC','HVAC Service','HVAC Installation','Gas Piping','New Construction','IAQ'));
create index if not exists jobs_service_type_idx on public.jobs(service_type);
