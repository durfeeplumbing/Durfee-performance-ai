create table if not exists public.service_titan_records (
  id uuid primary key default gen_random_uuid(),
  resource text not null,
  external_id text not null,
  payload jsonb not null,
  external_modified_at timestamptz,
  synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (resource, external_id)
);

create index if not exists service_titan_records_resource_idx on public.service_titan_records(resource);
create index if not exists service_titan_records_synced_at_idx on public.service_titan_records(synced_at desc);

create table if not exists public.service_titan_sync_runs (
  id uuid primary key default gen_random_uuid(),
  resource text not null,
  status text not null check (status in ('running','success','failed')),
  records_seen integer not null default 0,
  records_upserted integer not null default 0,
  error text,
  requested_by uuid,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists service_titan_sync_runs_started_idx on public.service_titan_sync_runs(started_at desc);

create table if not exists public.service_titan_integration_state (
  singleton boolean primary key default true check (singleton = true),
  environment text not null check (environment in ('integration','production')),
  tenant_id text not null,
  last_successful_sync timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);

alter table public.service_titan_records enable row level security;
alter table public.service_titan_sync_runs enable row level security;
alter table public.service_titan_integration_state enable row level security;

drop policy if exists service_titan_records_owner_read on public.service_titan_records;
create policy service_titan_records_owner_read on public.service_titan_records
for select to authenticated
using (public.has_permission_for_current_user('manage_permissions'));

drop policy if exists service_titan_sync_runs_owner_read on public.service_titan_sync_runs;
create policy service_titan_sync_runs_owner_read on public.service_titan_sync_runs
for select to authenticated
using (public.has_permission_for_current_user('manage_permissions'));

drop policy if exists service_titan_state_owner_read on public.service_titan_integration_state;
create policy service_titan_state_owner_read on public.service_titan_integration_state
for select to authenticated
using (public.has_permission_for_current_user('manage_permissions'));

create or replace function public.upsert_service_titan_resource(
  p_resource text,
  p_records jsonb,
  p_environment text,
  p_tenant_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_external_id text;
  v_modified timestamptz;
  v_seen integer := 0;
  v_upserted integer := 0;
  v_run_id uuid;
begin
  if not public.has_permission_for_current_user('manage_permissions') then
    raise exception 'Owner permission required';
  end if;
  if p_resource not in ('technicians','business_units') then
    raise exception 'Unsupported ServiceTitan resource';
  end if;
  if p_environment not in ('integration','production') then
    raise exception 'Invalid ServiceTitan environment';
  end if;
  if jsonb_typeof(p_records) <> 'array' then
    raise exception 'ServiceTitan records must be a JSON array';
  end if;

  insert into public.service_titan_sync_runs(resource,status,requested_by)
  values (p_resource,'running',auth.uid()) returning id into v_run_id;

  for v_item in select value from jsonb_array_elements(p_records)
  loop
    v_seen := v_seen + 1;
    v_external_id := nullif(v_item->>'id','');
    if v_external_id is null then
      continue;
    end if;
    begin
      v_modified := nullif(v_item->>'modifiedOn','')::timestamptz;
    exception when others then
      v_modified := null;
    end;

    insert into public.service_titan_records(resource,external_id,payload,external_modified_at,synced_at)
    values (p_resource,v_external_id,v_item,v_modified,now())
    on conflict (resource,external_id) do update
      set payload = excluded.payload,
          external_modified_at = excluded.external_modified_at,
          synced_at = now();
    v_upserted := v_upserted + 1;
  end loop;

  insert into public.service_titan_integration_state(singleton,environment,tenant_id,last_successful_sync,last_error,updated_at)
  values (true,p_environment,p_tenant_id,now(),null,now())
  on conflict (singleton) do update
    set environment = excluded.environment,
        tenant_id = excluded.tenant_id,
        last_successful_sync = excluded.last_successful_sync,
        last_error = null,
        updated_at = now();

  update public.service_titan_sync_runs
    set status='success', records_seen=v_seen, records_upserted=v_upserted, completed_at=now()
    where id=v_run_id;

  return jsonb_build_object('runId',v_run_id,'resource',p_resource,'seen',v_seen,'upserted',v_upserted);
exception when others then
  if v_run_id is not null then
    update public.service_titan_sync_runs set status='failed', error=sqlerrm, completed_at=now() where id=v_run_id;
  end if;
  raise;
end;
$$;

revoke all on function public.upsert_service_titan_resource(text,jsonb,text,text) from public;
grant execute on function public.upsert_service_titan_resource(text,jsonb,text,text) to authenticated;
