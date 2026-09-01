create or replace function private.service_titan_sync_status_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_counts jsonb; v_total bigint;
begin
  if not public.has_permission_for_current_user('manage_permissions') then raise exception 'Owner permission required'; end if;
  select coalesce(jsonb_object_agg(resource,record_count),'{}'::jsonb),coalesce(sum(record_count),0)
  into v_counts,v_total
  from (
    select resource,count(*)::bigint record_count
    from public.service_titan_records
    where resource in('technicians','business_units','customers','locations','jobs','appointments','estimates','job_timesheets','job_splits','invoices','payments','memberships')
    group by resource
  ) s;
  return jsonb_build_object('counts',v_counts,'totalCached',v_total);
end;
$$;
