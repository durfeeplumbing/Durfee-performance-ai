create table if not exists public.service_titan_record_mappings (
  id uuid primary key default gen_random_uuid(),
  resource text not null,
  external_id text not null,
  local_table text not null,
  local_id uuid,
  match_status text not null default 'unmatched' check (match_status in ('unmatched','candidate','matched','ignored','conflict')),
  match_method text,
  confidence numeric(5,4),
  notes text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(resource, external_id, local_table)
);
create index if not exists service_titan_record_mappings_status_idx on public.service_titan_record_mappings(resource,match_status);
create index if not exists service_titan_record_mappings_local_idx on public.service_titan_record_mappings(local_table,local_id);
alter table public.service_titan_record_mappings enable row level security;
drop policy if exists service_titan_record_mappings_owner_read on public.service_titan_record_mappings;
create policy service_titan_record_mappings_owner_read on public.service_titan_record_mappings for select to authenticated using (public.has_permission_for_current_user('manage_permissions'));

create or replace function public.refresh_service_titan_customer_mapping_candidates()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_count integer := 0;
begin
  if not public.has_permission_for_current_user('manage_permissions') then raise exception 'Owner permission required'; end if;
  insert into public.service_titan_record_mappings(resource,external_id,local_table,local_id,match_status,match_method,confidence,updated_at)
  select 'customers', r.external_id, 'customers', c.id,
    case when count(*) over(partition by r.external_id)=1 then 'candidate' else 'conflict' end,
    'normalized_email_or_phone',
    case when lower(nullif(r.payload->>'email',''))=lower(nullif(c.email,'')) and regexp_replace(coalesce(r.payload->>'phone',''),'\D','','g')=regexp_replace(coalesce(c.phone,''),'\D','','g') then 0.99 else 0.90 end,
    now()
  from public.service_titan_records r
  join public.customers c on
    (nullif(r.payload->>'email','') is not null and lower(r.payload->>'email')=lower(coalesce(c.email,'')))
    or
    (length(regexp_replace(coalesce(r.payload->>'phone',''),'\D','','g')) >= 10 and regexp_replace(coalesce(r.payload->>'phone',''),'\D','','g')=regexp_replace(coalesce(c.phone,''),'\D','','g'))
  where r.resource='customers'
  on conflict(resource,external_id,local_table) do update set
    local_id=excluded.local_id, match_status=excluded.match_status, match_method=excluded.match_method, confidence=excluded.confidence, updated_at=now()
  where service_titan_record_mappings.match_status in ('unmatched','candidate','conflict');
  get diagnostics v_count = row_count;
  insert into public.service_titan_record_mappings(resource,external_id,local_table,match_status,updated_at)
  select 'customers',r.external_id,'customers','unmatched',now() from public.service_titan_records r
  where r.resource='customers' and not exists(select 1 from public.service_titan_record_mappings m where m.resource='customers' and m.external_id=r.external_id and m.local_table='customers')
  on conflict do nothing;
  return jsonb_build_object('candidatesRefreshed',v_count);
end $$;
revoke all on function public.refresh_service_titan_customer_mapping_candidates() from public;
grant execute on function public.refresh_service_titan_customer_mapping_candidates() to authenticated;
