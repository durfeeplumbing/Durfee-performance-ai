create or replace function public.service_titan_technician_sales_performance(p_days integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days integer := least(greatest(coalesce(p_days,30),1),365);
  v_since timestamptz := now() - make_interval(days => v_days);
  v_result jsonb;
begin
  if not public.has_permission_for_current_user('view_team') then
    raise exception 'permission denied';
  end if;

  select coalesce(jsonb_agg(row_data order by revenue desc, technician_name), '[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'technicianId', t.external_id,
      'name', coalesce(nullif(t.payload->>'name',''), concat_ws(' ', t.payload->>'firstName', t.payload->>'lastName')),
      'active', t.payload->'active',
      'businessUnitId', t.payload->>'businessUnitId',
      'soldJobs', count(j.external_id),
      'completedSoldJobs', count(j.external_id) filter (where nullif(j.payload->>'completedOn','') is not null),
      'revenue', coalesce(sum(case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else 0 end),0),
      'averageTicket', coalesce(avg(case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else null end),0),
      'lastSoldJobAt', max(nullif(j.payload->>'completedOn','')::timestamptz)
    ) as row_data,
    coalesce(nullif(t.payload->>'name',''), concat_ws(' ', t.payload->>'firstName', t.payload->>'lastName')) as technician_name,
    coalesce(sum(case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else 0 end),0) as revenue
    from public.service_titan_records t
    left join public.service_titan_records j
      on j.resource='jobs'
     and j.payload->>'soldById'=t.external_id
     and coalesce(nullif(j.payload->>'completedOn','')::timestamptz, nullif(j.payload->>'createdOn','')::timestamptz) >= v_since
    where t.resource='technicians'
    group by t.external_id, t.payload
  ) s;
  return v_result;
end;
$$;

revoke all on function public.service_titan_technician_sales_performance(integer) from public, anon;
grant execute on function public.service_titan_technician_sales_performance(integer) to authenticated;

create or replace function public.service_titan_ar_aging(p_limit integer default 200)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,200),1),500);
  v_result jsonb;
begin
  if not public.has_permission_for_current_user('view_accounting') then
    raise exception 'permission denied';
  end if;

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'current', coalesce(sum(balance) filter (where age_days <= 0),0),
      'days1to30', coalesce(sum(balance) filter (where age_days between 1 and 30),0),
      'days31to60', coalesce(sum(balance) filter (where age_days between 31 and 60),0),
      'days61to90', coalesce(sum(balance) filter (where age_days between 61 and 90),0),
      'days90plus', coalesce(sum(balance) filter (where age_days > 90),0),
      'totalOpen', coalesce(sum(balance),0),
      'openInvoices', count(*)
    ),
    'invoices', coalesce(jsonb_agg(jsonb_build_object(
      'externalId', external_id,
      'referenceNumber', reference_number,
      'customerId', customer_id,
      'customerName', customer_name,
      'invoiceDate', invoice_date,
      'dueDate', due_date,
      'ageDays', age_days,
      'total', total,
      'balance', balance,
      'jobId', job_id
    ) order by age_days desc, balance desc) filter (where rn <= v_limit), '[]'::jsonb)
  ) into v_result
  from (
    select x.*, row_number() over(order by age_days desc, balance desc) rn
    from (
      select
        r.external_id,
        r.payload->>'referenceNumber' reference_number,
        coalesce(r.payload->'customer'->>'id', r.payload->>'customerId') customer_id,
        coalesce(r.payload->'customer'->>'name', r.payload->>'customerName') customer_name,
        nullif(r.payload->>'invoiceDate','')::date invoice_date,
        nullif(r.payload->>'dueDate','')::date due_date,
        greatest(0, current_date - coalesce(nullif(r.payload->>'dueDate','')::date, nullif(r.payload->>'invoiceDate','')::date, current_date)) age_days,
        case when coalesce(r.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r.payload->>'total')::numeric else 0 end total,
        case when coalesce(r.payload->>'balance','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r.payload->>'balance')::numeric else 0 end balance,
        coalesce(r.payload->'job'->>'id', r.payload->>'jobId') job_id
      from public.service_titan_records r
      where r.resource='invoices'
        and case when coalesce(r.payload->>'balance','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r.payload->>'balance')::numeric else 0 end > 0
    ) x
  ) q;

  return coalesce(v_result, jsonb_build_object('summary', jsonb_build_object('current',0,'days1to30',0,'days31to60',0,'days61to90',0,'days90plus',0,'totalOpen',0,'openInvoices',0),'invoices','[]'::jsonb));
end;
$$;

revoke all on function public.service_titan_ar_aging(integer) from public, anon;
grant execute on function public.service_titan_ar_aging(integer) to authenticated;
