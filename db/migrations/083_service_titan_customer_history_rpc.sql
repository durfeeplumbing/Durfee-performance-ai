create or replace function public.get_service_titan_customer_history(p_customer_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'customer', (select payload from public.service_titan_records where resource='customers' and external_id=p_customer_id limit 1),
    'locations', coalesce((select jsonb_agg(payload order by synced_at desc) from public.service_titan_records where resource='locations' and payload->>'customerId'=p_customer_id), '[]'::jsonb),
    'jobs', coalesce((select jsonb_agg(payload order by nullif(payload->>'completedOn','') desc nulls last) from public.service_titan_records where resource='jobs' and payload->>'customerId'=p_customer_id), '[]'::jsonb),
    'appointments', coalesce((select jsonb_agg(payload order by nullif(payload->>'start','') desc nulls last) from public.service_titan_records where resource='appointments' and payload->>'customerId'=p_customer_id), '[]'::jsonb),
    'invoices', coalesce((select jsonb_agg(payload order by nullif(payload->>'invoiceDate','') desc nulls last) from public.service_titan_records where resource='invoices' and coalesce(payload->'customer'->>'id', payload->>'customerId')=p_customer_id), '[]'::jsonb),
    'openBalance', coalesce((select sum(case when coalesce(payload->>'balance','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (payload->>'balance')::numeric else 0 end) from public.service_titan_records where resource='invoices' and coalesce(payload->'customer'->>'id', payload->>'customerId')=p_customer_id),0),
    'lifetimeRevenue', coalesce((select sum(case when coalesce(payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (payload->>'total')::numeric else 0 end) from public.service_titan_records where resource='invoices' and coalesce(payload->'customer'->>'id', payload->>'customerId')=p_customer_id),0)
  );
$$;
revoke execute on function public.get_service_titan_customer_history(text) from public, anon;
grant execute on function public.get_service_titan_customer_history(text) to authenticated;
