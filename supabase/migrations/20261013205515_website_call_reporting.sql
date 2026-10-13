-- Website intent is separate from confirmed ServiceTitan call attribution.
create table public.website_events (
 id uuid primary key, session_id uuid not null,
 event_kind text not null check(event_kind in ('page_view','call_click','text_click','form_open','scheduler_open')),
 page_path text not null check(length(page_path)<=512),entry_path text not null check(length(entry_path)<=512),
 source text,medium text,campaign text,received_at timestamptz not null default now()
);
create index website_events_received_idx on public.website_events(received_at desc);
create index website_events_session_idx on public.website_events(session_id,received_at desc);
alter table public.website_events enable row level security;
revoke all on public.website_events from public,anon,authenticated;
grant select,insert,delete on public.website_events to service_role;
create table public.website_servicetitan_records (
 kind text not null check(kind in ('call','attributed_lead')),external_id text not null,payload jsonb not null,
 occurred_at timestamptz,environment text not null check(environment in ('production','integration')),
 synced_at timestamptz not null default now(),primary key(kind,external_id,environment)
);
create index website_st_records_date_idx on public.website_servicetitan_records(occurred_at desc);
alter table public.website_servicetitan_records enable row level security;
revoke all on public.website_servicetitan_records from public,anon,authenticated;
grant select,insert,update on public.website_servicetitan_records to service_role;
create table public.website_sync_health (
 name text primary key, status text not null,last_attempt_at timestamptz not null default now(),last_success_at timestamptz,
 detail text,records integer not null default 0
);
alter table public.website_sync_health enable row level security;
revoke all on public.website_sync_health from public,anon,authenticated;
grant select,insert,update on public.website_sync_health to service_role;
-- Only server-side ingestion; deduplicate retries and bound each anonymous session.
create function public.capture_website_event(p_event jsonb) returns boolean
language plpgsql security invoker set search_path='' as $$
declare sid uuid := (p_event->>'session_id')::uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(sid::text,0));
 if (select count(*) from public.website_events where session_id=sid and received_at>now()-interval '1 hour')>=180 then return false; end if;
 insert into public.website_events(id,session_id,event_kind,page_path,entry_path,source,medium,campaign)
 values((p_event->>'id')::uuid,sid,p_event->>'event_kind',p_event->>'page_path',p_event->>'entry_path',left(p_event->>'source',128),left(p_event->>'medium',128),left(p_event->>'campaign',128)) on conflict(id) do nothing;
 return true;
end $$;
revoke all on function public.capture_website_event(jsonb) from public,anon,authenticated;
grant execute on function public.capture_website_event(jsonb) to service_role;
