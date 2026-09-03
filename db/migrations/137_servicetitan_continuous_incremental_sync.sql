create table if not exists public.service_titan_incremental_sync_state (
  resource text primary key,
  enabled boolean not null default true,
  cursor_at timestamptz,
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  last_records_seen integer not null default 0,
  last_error text,
  consecutive_failures integer not null default 0,
  updated_at timestamptz not null default now(),
  check (resource in ('customers','locations','jobs','appointments','estimates','invoices','payments','memberships'))
);

alter table public.service_titan_incremental_sync_state enable row level security;
revoke all on public.service_titan_incremental_sync_state from anon, authenticated;
grant select, insert, update, delete on public.service_titan_incremental_sync_state to service_role;

drop policy if exists service_titan_incremental_state_owner_read on public.service_titan_incremental_sync_state;
create policy service_titan_incremental_state_owner_read on public.service_titan_incremental_sync_state
for select to authenticated
using (public.has_permission_for_current_user('manage_permissions'));

insert into public.service_titan_incremental_sync_state(resource)
select resource from unnest(array['customers','locations','jobs','appointments','estimates','invoices','payments','memberships']::text[]) resource
on conflict (resource) do nothing;

create table if not exists public.service_titan_incremental_sync_guard (
  singleton boolean primary key default true check (singleton = true),
  lease_token uuid,
  lease_expires_at timestamptz,
  last_started_at timestamptz,
  last_completed_at timestamptz,
  last_status text check (last_status in ('running','success','partial_error','failed')),
  last_error text,
  updated_at timestamptz not null default now()
);

alter table public.service_titan_incremental_sync_guard enable row level security;
revoke all on public.service_titan_incremental_sync_guard from anon, authenticated;
grant select, insert, update, delete on public.service_titan_incremental_sync_guard to service_role;

insert into public.service_titan_incremental_sync_guard(singleton) values (true)
on conflict (singleton) do nothing;

create or replace function private.claim_service_titan_incremental_sync(p_lease_minutes integer default 8)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_token uuid := gen_random_uuid();
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required'; end if;
  update public.service_titan_incremental_sync_guard
  set lease_token=v_token,
      lease_expires_at=now()+make_interval(mins=>greatest(2,least(coalesce(p_lease_minutes,8),30))),
      last_started_at=now(),
      last_status='running',
      last_error=null,
      updated_at=now()
  where singleton=true and (lease_expires_at is null or lease_expires_at < now())
  returning lease_token into v_token;
  if not found then return null; end if;
  return v_token;
end;
$$;

create or replace function public.claim_service_titan_incremental_sync(p_lease_minutes integer default 8)
returns uuid
language sql
security definer
set search_path=''
as $$ select private.claim_service_titan_incremental_sync(p_lease_minutes) $$;
revoke all on function public.claim_service_titan_incremental_sync(integer) from public, anon, authenticated;
grant execute on function public.claim_service_titan_incremental_sync(integer) to service_role;

create or replace function private.finish_service_titan_incremental_sync(p_lease_token uuid,p_status text,p_error text default null)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_status not in ('success','partial_error','failed') then raise exception 'Invalid sync status'; end if;
  update public.service_titan_incremental_sync_guard
  set lease_token=null,lease_expires_at=null,last_completed_at=now(),last_status=p_status,last_error=left(p_error,2000),updated_at=now()
  where singleton=true and lease_token=p_lease_token;
end;
$$;

create or replace function public.finish_service_titan_incremental_sync(p_lease_token uuid,p_status text,p_error text default null)
returns void
language sql
security definer
set search_path=''
as $$ select private.finish_service_titan_incremental_sync(p_lease_token,p_status,p_error) $$;
revoke all on function public.finish_service_titan_incremental_sync(uuid,text,text) from public, anon, authenticated;
grant execute on function public.finish_service_titan_incremental_sync(uuid,text,text) to service_role;

create or replace function private.upsert_service_titan_resource(p_resource text,p_records jsonb,p_environment text,p_tenant_id text)
returns jsonb
language plpgsql
security definer
set search_path=''
set statement_timeout='20s'
as $$
declare v_seen integer:=0; v_upserted integer:=0; v_run_id uuid;
begin
  if coalesce(auth.role(),'') <> 'service_role' and not public.has_permission_for_current_user('manage_permissions') then raise exception 'Owner permission required'; end if;
  if p_resource not in('technicians','business_units','customers','locations','jobs','appointments','invoices','payments','memberships','job_timesheets','job_splits','estimates','pricebook_categories','pricebook_services','pricebook_materials','pricebook_equipment') then raise exception 'Unsupported ServiceTitan resource'; end if;
  if p_environment not in('integration','production') then raise exception 'Invalid ServiceTitan environment'; end if;
  if jsonb_typeof(p_records)<>'array' then raise exception 'ServiceTitan records must be a JSON array'; end if;
  select count(*) into v_seen from jsonb_array_elements(p_records);
  insert into public.service_titan_sync_runs(resource,status,requested_by) values(p_resource,'running',auth.uid()) returning id into v_run_id;
  with incoming as(
    select value item from jsonb_array_elements(p_records) where nullif(value->>'id','') is not null
  ),upserted as(
    insert into public.service_titan_records(resource,external_id,payload,external_modified_at,synced_at)
    select p_resource,item->>'id',item,
      case when coalesce(item->>'modifiedOn','') ~ '^\d{4}-\d{2}-\d{2}T' then (item->>'modifiedOn')::timestamptz else null end,
      now()
    from incoming
    on conflict(resource,external_id) do update set payload=excluded.payload,external_modified_at=excluded.external_modified_at,synced_at=excluded.synced_at
    returning 1
  ) select count(*) into v_upserted from upserted;
  insert into public.service_titan_integration_state(singleton,environment,tenant_id,last_successful_sync,last_error,updated_at)
  values(true,p_environment,p_tenant_id,now(),null,now())
  on conflict(singleton) do update set environment=excluded.environment,tenant_id=excluded.tenant_id,last_successful_sync=excluded.last_successful_sync,last_error=null,updated_at=now();
  update public.service_titan_sync_runs set status='success',records_seen=v_seen,records_upserted=v_upserted,completed_at=now() where id=v_run_id;
  return jsonb_build_object('runId',v_run_id,'resource',p_resource,'seen',v_seen,'upserted',v_upserted);
end;
$$;

grant execute on function public.upsert_service_titan_resource(text,jsonb,text,text) to service_role;

create index if not exists service_titan_incremental_success_idx on public.service_titan_incremental_sync_state(last_success_at desc);
