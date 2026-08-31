create or replace function public.service_titan_customer_directory(p_limit integer default 100, p_search text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,100),1),250);
  v_search text := nullif(btrim(coalesce(p_search,'')), '');
  v_result jsonb;
begin
  if not public.has_permission_for_current_user('view_customers') then
    raise exception 'permission denied';
  end if;
  select coalesce(jsonb_agg(x.row_data order by x.sort_name, x.external_id), '[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'externalId', c.external_id,
      'name', c.payload->>'name',
      'type', c.payload->>'type',
      'active', c.payload->'active',
      'balance', case when coalesce(c.payload->>'balance','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (c.payload->>'balance')::numeric else 0 end,
      'address', c.payload->'address',
      'jobCount', coalesce(j.job_count,0),
      'lastJobAt', j.last_job_at,
      'syncedAt', c.synced_at
    ) as row_data,
    lower(coalesce(c.payload->>'name','')) as sort_name,
    c.external_id
    from public.service_titan_records c
    left join lateral (
      select count(*)::integer as job_count,
             max(nullif(jr.payload->>'completedOn','')::timestamptz) as last_job_at
      from public.service_titan_records jr
      where jr.resource='jobs' and jr.payload->>'customerId'=c.external_id
    ) j on true
    where c.resource='customers'
      and (v_search is null
        or c.payload->>'name' ilike '%'||v_search||'%'
        or c.external_id ilike '%'||v_search||'%'
        or c.payload->'address'->>'street' ilike '%'||v_search||'%'
        or c.payload->'address'->>'city' ilike '%'||v_search||'%')
    order by lower(coalesce(c.payload->>'name','')), c.external_id
    limit v_limit
  ) x;
  return v_result;
end;
$$;
revoke all on function public.service_titan_customer_directory(integer,text) from public, anon;
grant execute on function public.service_titan_customer_directory(integer,text) to authenticated;
