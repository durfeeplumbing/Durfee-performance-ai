create or replace function public.match_customer_by_phone_for_provider(p_phone text)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select c.id
  from public.customers c
  where regexp_replace(coalesce(c.phone,''), '[^0-9]', '', 'g') =
        regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g')
     or right(regexp_replace(coalesce(c.phone,''), '[^0-9]', '', 'g'),10) =
        right(regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g'),10)
  order by c.created_at desc nulls last
  limit 1;
$$;
revoke all on function public.match_customer_by_phone_for_provider(text) from public, anon, authenticated;
grant execute on function public.match_customer_by_phone_for_provider(text) to service_role;
