create or replace function public.service_titan_jobs_fallback(p_limit integer default 100)
returns table(
  external_id text,
  job_number text,
  status text,
  summary text,
  total numeric,
  customer_name text,
  created_on timestamptz,
  modified_on timestamptz
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if not public.has_permission_for_current_user('view_jobs') then
    raise exception 'Jobs permission required';
  end if;
  return query
  select
    j.external_id,
    coalesce(j.payload->>'jobNumber',j.external_id),
    coalesce(j.payload->>'jobStatus','Unknown'),
    nullif(j.payload->>'summary',''),
    case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else 0 end,
    c.payload->>'name',
    case when coalesce(j.payload->>'createdOn','') <> '' then (j.payload->>'createdOn')::timestamptz else null end,
    case when coalesce(j.payload->>'modifiedOn','') <> '' then (j.payload->>'modifiedOn')::timestamptz else null end
  from public.service_titan_records j
  left join public.service_titan_records c
    on c.resource='customers' and c.external_id=j.payload->>'customerId'
  where j.resource='jobs'
  order by coalesce((j.payload->>'modifiedOn')::timestamptz,j.synced_at) desc
  limit greatest(1,least(coalesce(p_limit,100),500));
end;
$$;

revoke all on function public.service_titan_jobs_fallback(integer) from public;
grant execute on function public.service_titan_jobs_fallback(integer) to authenticated;

create or replace function public.service_titan_schedule_fallback(p_start timestamptz,p_end timestamptz)
returns table(
  appointment_id text,
  job_external_id text,
  job_number text,
  appointment_status text,
  job_status text,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  arrival_start timestamptz,
  arrival_end timestamptz,
  customer_name text,
  service_address text,
  summary text,
  total numeric
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if not public.has_permission_for_current_user('view_schedule') then
    raise exception 'Schedule permission required';
  end if;
  if p_start is null or p_end is null or p_end <= p_start or p_end > p_start + interval '31 days' then
    raise exception 'Invalid schedule window';
  end if;
  return query
  select
    a.external_id,
    j.external_id,
    coalesce(j.payload->>'jobNumber',j.external_id),
    coalesce(a.payload->>'status','Unknown'),
    coalesce(j.payload->>'jobStatus','Unknown'),
    (a.payload->>'start')::timestamptz,
    nullif(a.payload->>'end','')::timestamptz,
    nullif(a.payload->>'arrivalWindowStart','')::timestamptz,
    nullif(a.payload->>'arrivalWindowEnd','')::timestamptz,
    c.payload->>'name',
    concat_ws(', ',nullif(l.payload#>>'{address,street}',''),nullif(l.payload#>>'{address,unit}',''),nullif(l.payload#>>'{address,city}',''),nullif(l.payload#>>'{address,state}',''),nullif(l.payload#>>'{address,zip}','')),
    nullif(j.payload->>'summary',''),
    case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else 0 end
  from public.service_titan_records a
  join public.service_titan_records j
    on j.resource='jobs' and j.external_id=a.payload->>'jobId'
  left join public.service_titan_records c
    on c.resource='customers' and c.external_id=j.payload->>'customerId'
  left join public.service_titan_records l
    on l.resource='locations' and l.external_id=j.payload->>'locationId'
  where a.resource='appointments'
    and coalesce(a.payload->>'active','true') <> 'false'
    and nullif(a.payload->>'start','') is not null
    and (a.payload->>'start')::timestamptz >= p_start
    and (a.payload->>'start')::timestamptz < p_end
  order by (a.payload->>'start')::timestamptz;
end;
$$;

revoke all on function public.service_titan_schedule_fallback(timestamptz,timestamptz) from public;
grant execute on function public.service_titan_schedule_fallback(timestamptz,timestamptz) to authenticated;
