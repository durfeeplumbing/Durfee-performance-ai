create or replace function public.service_titan_technician_productivity(p_days integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days,30),365)));
  v_result jsonb;
begin
  if not public.has_permission_for_current_user('view_team') then
    raise exception 'Team permission required';
  end if;

  with techs as (
    select external_id as technician_id,
      coalesce(nullif(payload->>'name',''), nullif(payload->>'displayName',''), 'Technician ' || external_id) as technician_name
    from public.service_titan_records where resource='technicians'
  ), ts as (
    select payload->>'technicianId' technician_id, payload->>'jobId' job_id,
      case when coalesce(payload->>'dispatchedOn','') ~ '^\d{4}-\d{2}-\d{2}T' then (payload->>'dispatchedOn')::timestamptz end dispatched_on,
      case when coalesce(payload->>'arrivedOn','') ~ '^\d{4}-\d{2}-\d{2}T' then (payload->>'arrivedOn')::timestamptz end arrived_on,
      case when coalesce(payload->>'doneOn','') ~ '^\d{4}-\d{2}-\d{2}T' then (payload->>'doneOn')::timestamptz end done_on
    from public.service_titan_records
    where resource='job_timesheets' and coalesce(payload->>'active','true') <> 'false'
  ), splits as (
    select payload->>'technicianId' technician_id, payload->>'jobId' job_id,
      case when coalesce(payload->>'split','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (payload->>'split')::numeric else 0 end split
    from public.service_titan_records where resource='job_splits' and coalesce(payload->>'active','true') <> 'false'
  ), jobs as (
    select external_id job_id,
      case when coalesce(payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (payload->>'total')::numeric else 0 end total,
      case when coalesce(payload->>'completedOn','') ~ '^\d{4}-\d{2}-\d{2}T' then (payload->>'completedOn')::timestamptz end completed_on
    from public.service_titan_records where resource='jobs'
  ), agg as (
    select t.technician_id, t.technician_name,
      count(distinct ts.job_id) filter (where ts.done_on >= v_since)::int jobs_completed,
      round(coalesce(sum(extract(epoch from (ts.done_on-ts.arrived_on))/3600.0) filter (where ts.done_on >= v_since and ts.arrived_on is not null and ts.done_on >= ts.arrived_on),0)::numeric,2) onsite_hours,
      round(coalesce(sum(extract(epoch from (ts.arrived_on-ts.dispatched_on))/3600.0) filter (where ts.done_on >= v_since and ts.dispatched_on is not null and ts.arrived_on is not null and ts.arrived_on >= ts.dispatched_on),0)::numeric,2) dispatch_to_arrival_hours,
      round(coalesce(sum(j.total * case when s.split > 1 then s.split/100.0 else s.split end) filter (where j.completed_on >= v_since),0),2) attributed_revenue
    from techs t left join ts on ts.technician_id=t.technician_id
    left join jobs j on j.job_id=ts.job_id
    left join splits s on s.job_id=ts.job_id and s.technician_id=t.technician_id
    group by t.technician_id,t.technician_name
  )
  select jsonb_build_object(
    'days',greatest(1, least(coalesce(p_days,30),365)), 'since',v_since,
    'timesheetRecords',(select count(*) from public.service_titan_records where resource='job_timesheets'),
    'splitRecords',(select count(*) from public.service_titan_records where resource='job_splits'),
    'technicians',coalesce(jsonb_agg(jsonb_build_object(
      'technicianId',technician_id,'name',technician_name,'jobsCompleted',jobs_completed,
      'onsiteHours',onsite_hours,'dispatchToArrivalHours',dispatch_to_arrival_hours,
      'attributedRevenue',attributed_revenue,
      'revenuePerOnsiteHour',case when onsite_hours>0 then round(attributed_revenue/onsite_hours,2) else 0 end
    ) order by attributed_revenue desc),'[]'::jsonb)
  ) into v_result from agg;
  return v_result;
end;
$$;

revoke execute on function public.service_titan_technician_productivity(integer) from public, anon;
grant execute on function public.service_titan_technician_productivity(integer) to authenticated;
