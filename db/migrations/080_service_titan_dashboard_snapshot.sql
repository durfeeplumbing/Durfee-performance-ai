create or replace function public.service_titan_dashboard_snapshot(p_since timestamptz default date_trunc('day', now()))
returns jsonb
language plpgsql
security invoker
stable
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.has_permission_for_current_user('manage_permissions') then
    raise exception 'Owner permission required';
  end if;

  select jsonb_build_object(
    'jobsCreatedToday', count(*) filter (
      where resource='jobs'
        and coalesce(payload->>'createdOn','') ~ '^\d{4}-\d{2}-\d{2}T'
        and (payload->>'createdOn')::timestamptz >= p_since
    ),
    'jobsCompletedToday', count(*) filter (
      where resource='jobs'
        and coalesce(payload->>'completedOn','') ~ '^\d{4}-\d{2}-\d{2}T'
        and (payload->>'completedOn')::timestamptz >= p_since
    ),
    'completedJobRevenueToday', coalesce(sum(
      case when resource='jobs'
        and coalesce(payload->>'completedOn','') ~ '^\d{4}-\d{2}-\d{2}T'
        and (payload->>'completedOn')::timestamptz >= p_since
        and coalesce(payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then (payload->>'total')::numeric else 0 end
    ),0),
    'invoiceTotalToday', coalesce(sum(
      case when resource='invoices'
        and coalesce(payload->>'invoiceDate','') ~ '^\d{4}-\d{2}-\d{2}'
        and (payload->>'invoiceDate')::timestamptz >= p_since
        and coalesce(payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then (payload->>'total')::numeric else 0 end
    ),0),
    'paymentsToday', coalesce(sum(
      case when resource='payments'
        and coalesce(payload->>'date','') ~ '^\d{4}-\d{2}-\d{2}'
        and (payload->>'date')::timestamptz >= p_since
        and coalesce(payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then (payload->>'total')::numeric else 0 end
    ),0),
    'openAr', coalesce(sum(
      case when resource='invoices'
        and coalesce(payload->>'balance','') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then greatest((payload->>'balance')::numeric,0) else 0 end
    ),0),
    'activeMemberships', count(*) filter (
      where resource='memberships'
        and (lower(coalesce(payload->>'status',''))='active' or lower(coalesce(payload->>'active',''))='true')
    ),
    'totalCustomers', count(*) filter (where resource='customers'),
    'totalJobs', count(*) filter (where resource='jobs'),
    'totalInvoices', count(*) filter (where resource='invoices'),
    'totalPayments', count(*) filter (where resource='payments'),
    'lastSyncedAt', max(synced_at)
  ) into v_result
  from public.service_titan_records
  where resource in ('jobs','invoices','payments','memberships','customers');

  return v_result;
end;
$$;

revoke execute on function public.service_titan_dashboard_snapshot(timestamptz) from public, anon;
grant execute on function public.service_titan_dashboard_snapshot(timestamptz) to authenticated;
