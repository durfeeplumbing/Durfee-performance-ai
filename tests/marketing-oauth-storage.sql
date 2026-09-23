begin;
set local role service_role;
set local request.jwt.claims = '{"role":"service_role"}';
select public.marketing_provider_save_oauth('google_ads','v1.validation.access','v1.validation.refresh',now()+interval '1 hour','Bearer',array['validation']);
select public.marketing_provider_save_oauth('google_ads','v1.validation.access.updated',null,now()+interval '1 hour','Bearer',array['validation']);
do $$
begin
  if not exists (
    select 1 from private.marketing_provider_oauth_tokens t
    join public.marketing_provider_connections c using (provider)
    where t.provider='google_ads'
      and t.access_token_ciphertext='v1.validation.access.updated'
      and t.refresh_token_ciphertext='v1.validation.refresh'
      and c.connection_status='authorized'
  ) then raise exception 'OAuth save or refresh-token preservation failed'; end if;
end $$;
reset role;
set local role authenticated;
do $$
begin
  begin
    perform public.marketing_provider_save_oauth('google_ads','v1.validation.denied');
    raise exception 'Authenticated user unexpectedly saved credentials';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role anon;
do $$
begin
  begin
    perform public.marketing_provider_save_oauth('google_ads','v1.validation.denied');
    raise exception 'Anonymous user unexpectedly saved credentials';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
rollback;
select 'Passed: service save, refresh preservation, authenticated denial, anonymous denial; all test writes rolled back' as validation;
