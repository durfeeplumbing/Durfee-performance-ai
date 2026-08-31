create or replace function public.zero_invoice_closeout_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_result jsonb; v_role text;
begin
  select role into v_role from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_role not in ('owner','manager') then raise exception 'Owner or manager approval required'; end if;
  if not (public.has_permission_for_current_user('manage_jobs') or public.has_permission_for_current_user('manage_billing')) then raise exception 'Manager permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('jobId',a.job_id,'status',a.status,'requestedAt',a.requested_at,'requestedBy',ru.name,'customerName',c.name,'serviceAddress',c.service_address,'serviceType',j.service_type,'serviceSummary',j.service_summary,'technicianName',tu.name,'invoiceTotal',coalesce(i.invoice_total,0),'managerNote',a.manager_note) order by a.requested_at asc),'[]'::jsonb) into v_result
  from public.zero_invoice_closeout_approvals a join public.jobs j on j.id=a.job_id left join public.customers c on c.id=j.customer_id left join public.users ru on ru.id=a.requested_by left join public.users tu on tu.id=j.technician_id left join lateral (select sum(total) invoice_total from public.invoices where job_id=j.id) i on true where a.status='requested' and a.consumed_at is null;
  return v_result;
end;
$$;
revoke execute on function public.zero_invoice_closeout_queue() from public, anon;
grant execute on function public.zero_invoice_closeout_queue() to authenticated;
