grant select, insert, update on table public.customer_communications to service_role;
revoke all on table public.customer_communications from anon, authenticated;

create table if not exists private.dialpad_webhook_events (
  event_key text primary key,
  provider_event_id text,
  event_timestamp timestamptz,
  payload jsonb not null,
  processed boolean not null default false,
  processing_error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);
revoke all on table private.dialpad_webhook_events from public, anon, authenticated;
grant select, insert, update on table private.dialpad_webhook_events to service_role;
create index if not exists dialpad_webhook_events_unprocessed_idx on private.dialpad_webhook_events (processed, received_at desc);

create or replace function private.update_customer_communication_delivery(
  p_id uuid,
  p_status text,
  p_provider text,
  p_provider_event_id text default null,
  p_from_address text default null,
  p_disposition text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.communication_access_allowed(true) then
    raise exception 'Permission denied';
  end if;
  if p_status not in ('sent','delivered','failed','completed') then
    raise exception 'Invalid delivery status';
  end if;
  update public.customer_communications
  set status=p_status,
      provider=nullif(btrim(p_provider),''),
      provider_event_id=coalesce(nullif(btrim(p_provider_event_id),''),provider_event_id),
      from_address=coalesce(nullif(btrim(p_from_address),''),from_address),
      disposition=coalesce(nullif(btrim(p_disposition),''),disposition),
      updated_at=now()
  where id=p_id and direction='outbound';
  if not found then raise exception 'Communication not found'; end if;
end;
$$;
revoke all on function private.update_customer_communication_delivery(uuid,text,text,text,text,text) from public, anon;
grant execute on function private.update_customer_communication_delivery(uuid,text,text,text,text,text) to authenticated;

create or replace function public.update_customer_communication_delivery(
  p_id uuid,
  p_status text,
  p_provider text,
  p_provider_event_id text default null,
  p_from_address text default null,
  p_disposition text default null
) returns void
language sql
security invoker
set search_path = ''
as $$
  select private.update_customer_communication_delivery(p_id,p_status,p_provider,p_provider_event_id,p_from_address,p_disposition);
$$;
revoke all on function public.update_customer_communication_delivery(uuid,text,text,text,text,text) from public, anon;
grant execute on function public.update_customer_communication_delivery(uuid,text,text,text,text,text) to authenticated;
