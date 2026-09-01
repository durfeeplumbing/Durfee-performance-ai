create or replace function private.upsert_service_titan_resource(p_resource text, p_records jsonb, p_environment text, p_tenant_id text)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='20s' as $$
declare v_seen integer:=0; v_upserted integer:=0; v_run_id uuid;
begin
  if not public.has_permission_for_current_user('manage_permissions') then raise exception 'Owner permission required'; end if;
  if p_resource not in('technicians','business_units','customers','locations','jobs','appointments','invoices','payments','memberships','job_timesheets','job_splits','estimates','pricebook_categories','pricebook_services','pricebook_materials','pricebook_equipment') then raise exception 'Unsupported ServiceTitan resource'; end if;
  if p_environment not in('integration','production') then raise exception 'Invalid ServiceTitan environment'; end if;
  if jsonb_typeof(p_records)<>'array' then raise exception 'ServiceTitan records must be a JSON array'; end if;
  select count(*) into v_seen from jsonb_array_elements(p_records);
  insert into public.service_titan_sync_runs(resource,status,requested_by) values(p_resource,'running',auth.uid()) returning id into v_run_id;
  with incoming as(select value item from jsonb_array_elements(p_records) where nullif(value->>'id','') is not null),upserted as(
    insert into public.service_titan_records(resource,external_id,payload,external_modified_at,synced_at)
    select p_resource,item->>'id',item,case when coalesce(item->>'modifiedOn','') ~ '^\d{4}-\d{2}-\d{2}T' then (item->>'modifiedOn')::timestamptz else null end,now()
    from incoming on conflict(resource,external_id) do update set payload=excluded.payload,external_modified_at=excluded.external_modified_at,synced_at=excluded.synced_at returning 1
  ) select count(*) into v_upserted from upserted;
  insert into public.service_titan_integration_state(singleton,environment,tenant_id,last_successful_sync,last_error,updated_at) values(true,p_environment,p_tenant_id,now(),null,now()) on conflict(singleton) do update set environment=excluded.environment,tenant_id=excluded.tenant_id,last_successful_sync=excluded.last_successful_sync,last_error=null,updated_at=now();
  update public.service_titan_sync_runs set status='success',records_seen=v_seen,records_upserted=v_upserted,completed_at=now() where id=v_run_id;
  return jsonb_build_object('runId',v_run_id,'resource',p_resource,'seen',v_seen,'upserted',v_upserted);
end$$;

create or replace function private.service_titan_sync_status_summary() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_counts jsonb; v_total bigint;
begin
  if not public.has_permission_for_current_user('manage_permissions') then raise exception 'Owner permission required'; end if;
  select coalesce(jsonb_object_agg(resource,record_count),'{}'::jsonb),coalesce(sum(record_count),0) into v_counts,v_total from (
    select resource,count(*)::bigint record_count from public.service_titan_records where resource in('technicians','business_units','customers','locations','jobs','appointments','invoices','payments','memberships','estimates') group by resource
  )s;
  return jsonb_build_object('counts',v_counts,'totalCached',v_total);
end$$;

create or replace function private.service_titan_estimate_funnel(p_days integer default 30) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_days integer:=least(greatest(coalesce(p_days,30),1),365); v_since timestamptz:=now()-make_interval(days=>v_days); v_result jsonb;
begin
  if not public.has_permission_for_current_user('view_team') then raise exception 'Team permission required'; end if;
  with estimates as (
    select r.external_id,r.payload,coalesce(nullif(r.payload->>'createdOn','')::timestamptz,r.synced_at) created_on,nullif(r.payload->>'soldOn','')::timestamptz sold_on,nullif(r.payload->>'soldBy','') sold_by,coalesce(nullif(r.payload->'status'->>'name',''),nullif(r.payload->>'status',''),'Unknown') status_name,case when coalesce(r.payload->>'subtotal','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r.payload->>'subtotal')::numeric else 0 end subtotal,case when coalesce(r.payload->>'tax','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r.payload->>'tax')::numeric else 0 end tax
    from public.service_titan_records r where r.resource='estimates' and coalesce(nullif(r.payload->>'createdOn','')::timestamptz,r.synced_at)>=v_since
  ),agg as (
    select count(*)::int estimates_created,count(*) filter(where sold_on is not null)::int sold_estimates,count(*) filter(where sold_on is null and lower(status_name) like 'dismiss%')::int dismissed_estimates,count(*) filter(where sold_on is null and lower(status_name) not like 'dismiss%')::int open_or_other_estimates,coalesce(sum(subtotal+tax) filter(where sold_on is not null),0) sold_revenue,coalesce(avg(subtotal+tax) filter(where sold_on is not null),0) average_sold_estimate from estimates
  ),statuses as (
    select coalesce(jsonb_object_agg(status_name,cnt),'{}'::jsonb) status_counts from (select status_name,count(*)::int cnt from estimates group by status_name order by status_name)q
  ),tech_sales as (
    select coalesce(jsonb_agg(row_data order by sold_revenue desc,technician_name),'[]'::jsonb) rows from (
      select t.external_id technician_id,coalesce(nullif(t.payload->>'name',''),concat_ws(' ',t.payload->>'firstName',t.payload->>'lastName'),'Technician '||t.external_id) technician_name,count(e.external_id)::int sold_estimates,coalesce(sum(e.subtotal+e.tax),0) sold_revenue,jsonb_build_object('technicianId',t.external_id,'name',coalesce(nullif(t.payload->>'name',''),concat_ws(' ',t.payload->>'firstName',t.payload->>'lastName'),'Technician '||t.external_id),'soldEstimates',count(e.external_id)::int,'soldRevenue',coalesce(sum(e.subtotal+e.tax),0),'averageSoldEstimate',coalesce(avg(e.subtotal+e.tax),0)) row_data
      from public.service_titan_records t left join estimates e on e.sold_by=t.external_id and e.sold_on is not null where t.resource='technicians' group by t.external_id,t.payload
    )x
  )
  select jsonb_build_object('days',v_days,'since',v_since,'estimatesCreated',a.estimates_created,'soldEstimates',a.sold_estimates,'dismissedEstimates',a.dismissed_estimates,'openOrOtherEstimates',a.open_or_other_estimates,'createdToSoldRate',case when a.estimates_created>0 then round(a.sold_estimates::numeric/a.estimates_created*100,1) else 0 end,'decidedCloseRate',case when (a.sold_estimates+a.dismissed_estimates)>0 then round(a.sold_estimates::numeric/(a.sold_estimates+a.dismissed_estimates)*100,1) else 0 end,'soldRevenue',a.sold_revenue,'averageSoldEstimate',a.average_sold_estimate,'statusCounts',s.status_counts,'technicians',t.rows) into v_result from agg a cross join statuses s cross join tech_sales t;
  return coalesce(v_result,jsonb_build_object('days',v_days,'estimatesCreated',0,'soldEstimates',0,'dismissedEstimates',0,'openOrOtherEstimates',0,'createdToSoldRate',0,'decidedCloseRate',0,'soldRevenue',0,'averageSoldEstimate',0,'statusCounts','{}'::jsonb,'technicians','[]'::jsonb));
end$$;

create or replace function public.service_titan_estimate_funnel(p_days integer default 30) returns jsonb language sql stable set search_path='' as $$select private.service_titan_estimate_funnel(p_days)$$;
revoke all on function private.service_titan_estimate_funnel(integer) from public,anon,authenticated;
revoke all on function public.service_titan_estimate_funnel(integer) from public,anon;
grant execute on function public.service_titan_estimate_funnel(integer) to authenticated;
