create or replace function public.job_callback_management_queue()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_role text; v_result jsonb;
begin
 select role into v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
 if v_role not in ('owner','manager') and not public.has_permission_for_current_user('manage_jobs') then raise exception 'Manager job permission required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'originalJobId',c.original_job_id,'callbackJobId',c.callback_job_id,'technicianId',c.original_technician_id,'technicianName',u.name,'reason',c.reason,'preventability',c.preventability,'callbackCost',c.callback_cost,'managerNote',c.manager_note,'reviewedAt',c.reviewed_at,'createdAt',c.created_at,'originalCustomer',oc.name,'originalServiceType',oj.service_type,'originalServiceSummary',oj.service_summary,'callbackCustomer',cc.name,'callbackServiceType',cj.service_type,'callbackServiceSummary',cj.service_summary) order by c.created_at desc),'[]'::jsonb) into v_result
 from public.job_callbacks c join public.jobs oj on oj.id=c.original_job_id join public.jobs cj on cj.id=c.callback_job_id left join public.users u on u.id=c.original_technician_id left join public.customers oc on oc.id=oj.customer_id left join public.customers cc on cc.id=cj.customer_id;
 return v_result;
end;$$;
revoke execute on function public.job_callback_management_queue() from public,anon;
grant execute on function public.job_callback_management_queue() to authenticated;