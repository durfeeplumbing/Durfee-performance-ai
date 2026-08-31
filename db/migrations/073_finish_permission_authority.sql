do $$
declare r record; d text; original text;
begin
  for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in (
    'add_purchase_order_line_atomic','update_purchase_order_line_atomic','remove_purchase_order_line_atomic',
    'create_employee_invite_atomic','revoke_employee_invite_atomic',
    'create_price_book_item_atomic','update_price_book_item_atomic','save_price_book_tier_atomic','create_price_book_learning_proposal_atomic',
    'record_customer_followup_atomic','reverse_ap_payment_atomic','reverse_job_cost_allocation_atomic','void_ap_entry_atomic','update_company_pricing_settings_atomic'
  ) loop
    original:=pg_get_functiondef(r.oid); d:=original;
    d:=regexp_replace(d,$re$if\s+([a-z_]+)\.id\s+is\s+null\s+or\s+\1\.role\s+not\s+in\s*\([^)]*\)\s+or\s+not\s+private\.has_permission\('([^']+)'\)\s+then\s+raise\s+exception\s+'Permission denied';\s*end\s+if;$re$,$rep$if \1.id is null then raise exception 'Employee identity unavailable'; end if; if not private.has_permission('\2') then raise exception 'Permission denied'; end if;$rep$,'i');
    d:=regexp_replace(d,$re$if\s+([a-z_]+)\.id\s+is\s+null\s+or\s+\1\.role\s+not\s+in\s*\([^)]*\)\s+then\s+raise\s+exception\s+'Not authorized';\s*end\s+if;$re$,$rep$if \1.id is null then raise exception 'Employee identity unavailable'; end if;$rep$,'i');
    if d=original then raise exception 'No historical role gate transformed in %',r.proname; end if;
    execute d;
  end loop;
end $$;

-- This legacy vendor-bill approval path predates the reconciled posting workflow and must not remain callable.
drop function if exists public.approve_vendor_bill_draft(uuid);
