alter function public.add_estimate_option_atomic_impl(uuid,text,text,numeric,numeric,uuid) set schema private;
alter function public.approve_estimate_option_internal_impl(uuid,uuid) set schema private;
alter function public.close_job_financially_impl(uuid) set schema private;
alter function public.create_estimate_acceptance_link_atomic_impl(uuid) set schema private;
alter function public.create_estimate_atomic_impl(uuid) set schema private;
alter function public.create_job_invoice_explicit_impl(uuid,numeric,boolean) set schema private;
alter function public.record_invoice_payment_impl(uuid,numeric,text,text) set schema private;
alter function public.revoke_estimate_acceptance_link_atomic_impl(uuid) set schema private;

create or replace function public.add_estimate_option_atomic(p_estimate_id uuid,p_tier text,p_description text,p_price numeric,p_cost numeric,p_price_book_tier_id uuid) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_estimates') then raise exception 'Permission denied'; end if; return private.add_estimate_option_atomic_impl(p_estimate_id,p_tier,p_description,p_price,p_cost,p_price_book_tier_id); end$$;
create or replace function public.approve_estimate_option_internal(p_estimate_id uuid,p_option_id uuid) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_estimates') then raise exception 'Permission denied'; end if; return private.approve_estimate_option_internal_impl(p_estimate_id,p_option_id); end$$;
create or replace function public.close_job_financially(p_job_id uuid) returns boolean language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_billing') then raise exception 'Permission denied'; end if; return private.close_job_financially_impl(p_job_id); end$$;
create or replace function public.create_estimate_acceptance_link_atomic(p_estimate_id uuid) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_estimates') then raise exception 'Permission denied'; end if; return private.create_estimate_acceptance_link_atomic_impl(p_estimate_id); end$$;
create or replace function public.create_estimate_atomic(p_job_id uuid) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_estimates') then raise exception 'Permission denied'; end if; return private.create_estimate_atomic_impl(p_job_id); end$$;
create or replace function public.create_job_invoice_explicit(p_job_id uuid,p_requested_total numeric,p_owner_price_exception boolean) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_billing') then raise exception 'Permission denied'; end if; return private.create_job_invoice_explicit_impl(p_job_id,p_requested_total,p_owner_price_exception); end$$;
create or replace function public.record_invoice_payment(p_invoice_id uuid,p_amount numeric,p_method text,p_reference text) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_billing') then raise exception 'Permission denied'; end if; return private.record_invoice_payment_impl(p_invoice_id,p_amount,p_method,p_reference); end$$;
create or replace function public.revoke_estimate_acceptance_link_atomic(p_link_id uuid) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_estimates') then raise exception 'Permission denied'; end if; return private.revoke_estimate_acceptance_link_atomic_impl(p_link_id); end$$;

revoke all on function private.add_estimate_option_atomic_impl(uuid,text,text,numeric,numeric,uuid) from public,anon,authenticated;
revoke all on function private.approve_estimate_option_internal_impl(uuid,uuid) from public,anon,authenticated;
revoke all on function private.close_job_financially_impl(uuid) from public,anon,authenticated;
revoke all on function private.create_estimate_acceptance_link_atomic_impl(uuid) from public,anon,authenticated;
revoke all on function private.create_estimate_atomic_impl(uuid) from public,anon,authenticated;
revoke all on function private.create_job_invoice_explicit_impl(uuid,numeric,boolean) from public,anon,authenticated;
revoke all on function private.record_invoice_payment_impl(uuid,numeric,text,text) from public,anon,authenticated;
revoke all on function private.revoke_estimate_acceptance_link_atomic_impl(uuid) from public,anon,authenticated;

grant execute on function public.add_estimate_option_atomic(uuid,text,text,numeric,numeric,uuid) to authenticated;
grant execute on function public.approve_estimate_option_internal(uuid,uuid) to authenticated;
grant execute on function public.close_job_financially(uuid) to authenticated;
grant execute on function public.create_estimate_acceptance_link_atomic(uuid) to authenticated;
grant execute on function public.create_estimate_atomic(uuid) to authenticated;
grant execute on function public.create_job_invoice_explicit(uuid,numeric,boolean) to authenticated;
grant execute on function public.record_invoice_payment(uuid,numeric,text,text) to authenticated;
grant execute on function public.revoke_estimate_acceptance_link_atomic(uuid) to authenticated;
