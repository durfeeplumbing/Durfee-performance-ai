-- Management-only ServiceTitan sales/recall analytics. These are descriptive snapshots,
-- not automatic personnel scores. Exact estimate conversion cannot be claimed until
-- estimate-status records are synced; jobsWithEstimate is therefore shown separately.
create or replace function public.service_titan_technician_sales_funnel(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_days integer:=least(greatest(coalesce(p_days,30),1),365); v_since timestamptz:=now()-make_interval(days=>v_days); v_result jsonb;
begin
 if not public.has_permission_for_current_user('view_team') then raise exception 'permission denied'; end if;
 select coalesce(jsonb_agg(x.row_data order by x.sold_revenue desc,x.technician_name),'[]'::jsonb) into v_result from (
  select coalesce(nullif(t.payload->>'name',''),concat_ws(' ',t.payload->>'firstName',t.payload->>'lastName')) technician_name,
   coalesce(sum(case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else 0 end),0) sold_revenue,
   jsonb_build_object('technicianId',t.external_id,'name',coalesce(nullif(t.payload->>'name',''),concat_ws(' ',t.payload->>'firstName',t.payload->>'lastName')),'jobsWithEstimate',count(j.external_id) filter(where jsonb_array_length(coalesce(j.payload->'estimateIds','[]'::jsonb))>0),'soldJobs',count(j.external_id) filter(where nullif(j.payload->>'soldById','') is not null),'completedSoldJobs',count(j.external_id) filter(where nullif(j.payload->>'soldById','') is not null and nullif(j.payload->>'completedOn','') is not null),'soldRevenue',coalesce(sum(case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else 0 end),0),'averageSoldTicket',coalesce(avg(case when coalesce(j.payload->>'total','') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j.payload->>'total')::numeric else null end),0),'recallJobs',count(j.external_id) filter(where nullif(j.payload->>'recallForId','') is not null)) row_data
  from public.service_titan_records t left join public.service_titan_records j on j.resource='jobs' and j.payload->>'soldById'=t.external_id and coalesce(nullif(j.payload->>'completedOn','')::timestamptz,nullif(j.payload->>'createdOn','')::timestamptz)>=v_since where t.resource='technicians' group by t.external_id,t.payload
 ) x; return v_result; end;$$;
revoke all on function public.service_titan_technician_sales_funnel(integer) from public,anon; grant execute on function public.service_titan_technician_sales_funnel(integer) to authenticated;

create or replace function public.service_titan_recall_snapshot(p_days integer default 90)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_days integer:=least(greatest(coalesce(p_days,90),1),365); v_since timestamptz:=now()-make_interval(days=>v_days); v_result jsonb;
begin
 if not public.has_permission_for_current_user('view_team') then raise exception 'permission denied'; end if;
 select jsonb_build_object('days',v_days,'recalls',count(*),'records',coalesce(jsonb_agg(jsonb_build_object('jobId',j.external_id,'jobNumber',j.payload->>'jobNumber','recallForId',j.payload->>'recallForId','summary',j.payload->>'summary','completedOn',j.payload->>'completedOn','soldById',j.payload->>'soldById') order by coalesce(nullif(j.payload->>'completedOn','')::timestamptz,nullif(j.payload->>'createdOn','')::timestamptz) desc),'[]'::jsonb)) into v_result from public.service_titan_records j where j.resource='jobs' and nullif(j.payload->>'recallForId','') is not null and coalesce(nullif(j.payload->>'completedOn','')::timestamptz,nullif(j.payload->>'createdOn','')::timestamptz)>=v_since;
 return coalesce(v_result,jsonb_build_object('days',v_days,'recalls',0,'records','[]'::jsonb)); end;$$;
revoke all on function public.service_titan_recall_snapshot(integer) from public,anon; grant execute on function public.service_titan_recall_snapshot(integer) to authenticated;
