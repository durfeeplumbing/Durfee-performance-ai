create or replace function public.ingest_dialpad_webhook_event(
  p_event_key text,
  p_provider_event_id text,
  p_event_timestamp timestamptz,
  p_payload jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_user <> 'service_role' then raise exception 'Permission denied'; end if;
  insert into private.dialpad_webhook_events(event_key,provider_event_id,event_timestamp,payload)
  values(p_event_key,p_provider_event_id,p_event_timestamp,coalesce(p_payload,'{}'::jsonb))
  on conflict(event_key) do update set payload=excluded.payload,event_timestamp=excluded.event_timestamp;
end;
$$;
revoke all on function public.ingest_dialpad_webhook_event(text,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.ingest_dialpad_webhook_event(text,text,timestamptz,jsonb) to service_role;

create or replace function public.finish_dialpad_webhook_event(p_event_key text,p_error text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_user <> 'service_role' then raise exception 'Permission denied'; end if;
  update private.dialpad_webhook_events
  set processed=(p_error is null),processing_error=nullif(left(coalesce(p_error,''),1000),''),processed_at=now()
  where event_key=p_event_key;
end;
$$;
revoke all on function public.finish_dialpad_webhook_event(text,text) from public,anon,authenticated;
grant execute on function public.finish_dialpad_webhook_event(text,text) to service_role;
