create or replace function public.upsert_service_titan_resource(
  p_resource text,
  p_records jsonb,
  p_environment text,
  p_tenant_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
set statement_timeout = '20s'
as $$
declare
  v_seen integer := 0;
  v_upserted integer := 0;
  v_run_id uuid;
begin
  if not public.has_permission_for_current_user('manage_permissions') then
    raise exception 'Owner permission required';
  end if;

  if p_resource not in (
    'technicians','business_units','customers','locations',
    'jobs','appointments','invoices','payments','memberships',
    'pricebook_categories','pricebook_services',
    'pricebook_materials','pricebook_equipment'
  ) then
    raise exception 'Unsupported ServiceTitan resource';
  end if;

  if p_environment not in ('integration','production') then
    raise exception 'Invalid ServiceTitan environment';
  end if;

  if jsonb_typeof(p_records) <> 'array' then
    raise exception 'ServiceTitan records must be a JSON array';
  end if;

  select count(*) into v_seen
  from jsonb_array_elements(p_records);

  insert into public.service_titan_sync_runs(resource,status,requested_by)
  values (p_resource,'running',auth.uid())
  returning id into v_run_id;

  with incoming as (
    select value as item
    from jsonb_array_elements(p_records)
    where nullif(value->>'id','') is not null
  ), upserted as (
    insert into public.service_titan_records(
      resource,external_id,payload,external_modified_at,synced_at
    )
    select
      p_resource,
      item->>'id',
      item,
      case
        when coalesce(item->>'modifiedOn','') ~ '^\d{4}-\d{2}-\d{2}T'
        then (item->>'modifiedOn')::timestamptz
        else null
      end,
      now()
    from incoming
    on conflict (resource,external_id) do update
      set payload=excluded.payload,
          external_modified_at=excluded.external_modified_at,
          synced_at=excluded.synced_at
    returning 1
  )
  select count(*) into v_upserted from upserted;

  insert into public.service_titan_integration_state(
    singleton,environment,tenant_id,last_successful_sync,last_error,updated_at
  )
  values (true,p_environment,p_tenant_id,now(),null,now())
  on conflict (singleton) do update
    set environment=excluded.environment,
        tenant_id=excluded.tenant_id,
        last_successful_sync=excluded.last_successful_sync,
        last_error=null,
        updated_at=now();

  update public.service_titan_sync_runs
  set status='success',
      records_seen=v_seen,
      records_upserted=v_upserted,
      completed_at=now()
  where id=v_run_id;

  return jsonb_build_object(
    'runId',v_run_id,
    'resource',p_resource,
    'seen',v_seen,
    'upserted',v_upserted
  );
end;
$$;

revoke execute on function public.upsert_service_titan_resource(text,jsonb,text,text)
from public, anon;

grant execute on function public.upsert_service_titan_resource(text,jsonb,text,text)
to authenticated;
