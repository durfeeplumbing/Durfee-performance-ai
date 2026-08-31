do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
      and p.proname not in ('get_estimate_acceptance','accept_estimate')
  loop
    execute format('revoke execute on function %s from anon, public', r.fn);
  end loop;
end $$;

-- Keep the two token-based customer estimate functions intentionally public.
grant execute on function public.get_estimate_acceptance(uuid) to anon, authenticated;
grant execute on function public.accept_estimate(uuid,uuid,text,text) to anon, authenticated;