do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as signature,p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
  loop
    if r.proname not in ('accept_estimate','get_estimate_acceptance') then
      execute format('revoke execute on function %s from anon',r.signature);
    end if;
  end loop;
end $$;

revoke execute on function public.accept_estimate(uuid,uuid,text,text) from public;
revoke execute on function public.get_estimate_acceptance(uuid) from public;
grant execute on function public.accept_estimate(uuid,uuid,text,text) to anon,authenticated;
grant execute on function public.get_estimate_acceptance(uuid) to anon,authenticated;

alter function public.assign_customer_code() set search_path=public,pg_temp;
alter function public.assign_vendor_code() set search_path=public,pg_temp;
