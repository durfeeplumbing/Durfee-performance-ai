alter function public.allocate_ap_to_job_impl(uuid,uuid,numeric,text,text) set schema private;
alter function public.record_ap_payment_impl(uuid,numeric,timestamptz,text,text,text) set schema private;
alter function public.review_and_approve_vendor_bill_impl(uuid,text,date,date,numeric,numeric,numeric,text,text) set schema private;
alter function public.reject_vendor_bill_atomic_impl(uuid,text) set schema private;

grant usage on schema private to authenticated;
grant execute on function private.allocate_ap_to_job_impl(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function private.record_ap_payment_impl(uuid,numeric,timestamptz,text,text,text) to authenticated;
grant execute on function private.review_and_approve_vendor_bill_impl(uuid,text,date,date,numeric,numeric,numeric,text,text) to authenticated;
grant execute on function private.reject_vendor_bill_atomic_impl(uuid,text) to authenticated;

create or replace function public.allocate_ap_to_job(p_ap_id uuid,p_job_id uuid,p_amount numeric,p_type text,p_notes text)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
  if not private.has_permission('manage_accounting') then raise exception 'Permission denied'; end if;
  return private.allocate_ap_to_job_impl(p_ap_id,p_job_id,p_amount,p_type,p_notes);
end$$;

create or replace function public.record_ap_payment(p_ap_id uuid,p_amount numeric,p_paid_at timestamptz,p_payment_method text,p_reference text,p_notes text)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
  if not private.has_permission('manage_accounting') then raise exception 'Permission denied'; end if;
  return private.record_ap_payment_impl(p_ap_id,p_amount,p_paid_at,p_payment_method,p_reference,p_notes);
end$$;

create or replace function public.review_and_approve_vendor_bill(p_bill_id uuid,p_invoice_number text,p_invoice_date date,p_due_date date,p_subtotal numeric,p_tax numeric,p_total numeric,p_account_code text,p_memo text)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
  if not private.has_permission('manage_accounting') then raise exception 'Permission denied'; end if;
  return private.review_and_approve_vendor_bill_impl(p_bill_id,p_invoice_number,p_invoice_date,p_due_date,p_subtotal,p_tax,p_total,p_account_code,p_memo);
end$$;

create or replace function public.reject_vendor_bill_atomic(p_bill_id uuid,p_reason text)
returns uuid language plpgsql security invoker set search_path='' as $$
begin
  if not private.has_permission('manage_accounting') then raise exception 'Permission denied'; end if;
  return private.reject_vendor_bill_atomic_impl(p_bill_id,p_reason);
end$$;

revoke all on function public.allocate_ap_to_job(uuid,uuid,numeric,text,text) from public,anon;
revoke all on function public.record_ap_payment(uuid,numeric,timestamptz,text,text,text) from public,anon;
revoke all on function public.review_and_approve_vendor_bill(uuid,text,date,date,numeric,numeric,numeric,text,text) from public,anon;
revoke all on function public.reject_vendor_bill_atomic(uuid,text) from public,anon;
grant execute on function public.allocate_ap_to_job(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.record_ap_payment(uuid,numeric,timestamptz,text,text,text) to authenticated;
grant execute on function public.review_and_approve_vendor_bill(uuid,text,date,date,numeric,numeric,numeric,text,text) to authenticated;
grant execute on function public.reject_vendor_bill_atomic(uuid,text) to authenticated;
