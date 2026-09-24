begin;
do $$
declare owner_auth_id uuid;
begin
  select auth_user_id into owner_auth_id from public.users
  where role='owner' and active and auth_user_id is not null
  order by id limit 1;
  if owner_auth_id is null then raise exception 'An active owner is required for this test'; end if;
  perform set_config('request.jwt.claim.sub',owner_auth_id::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_auth_id,'role','authenticated')::text,true);
end $$;
set local role authenticated;
do $$
begin
  if not exists (select 1 from public.marketing_provider_connection_summary() where provider='google_ads') then
    raise exception 'Owner cannot read the Google connection';
  end if;
  perform * from public.marketing_sync_queue_summary();
  if has_table_privilege('authenticated','private.marketing_provider_oauth_tokens','select') then
    raise exception 'User gained token-vault access';
  end if;
  if has_table_privilege('authenticated','public.marketing_provider_connections','update') then
    raise exception 'User gained connection write access';
  end if;
end $$;
reset role;
do $$
declare unmapped_subject uuid := gen_random_uuid();
begin
  perform set_config('request.jwt.claim.sub',unmapped_subject::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',unmapped_subject,'role','authenticated')::text,true);
end $$;
set local role authenticated;
do $$
begin
  if exists (select 1 from public.marketing_provider_connection_summary())
    or exists (select 1 from public.marketing_sync_queue_summary())
    or exists (select provider from public.marketing_provider_connections)
    or exists (select provider from public.marketing_conversion_sync_queue)
    or exists (select id from public.marketing_conversion_events) then
    raise exception 'Unmapped account can read restricted marketing data';
  end if;
end $$;
reset role;
set local role anon;
do $$
begin
  begin
    perform * from public.marketing_provider_connection_summary();
    raise exception 'Anonymous account can call connection summary';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.marketing_sync_queue_summary();
    raise exception 'Anonymous account can call queue summary';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
rollback;
select 'Passed: owner reads both summaries, unmapped accounts see no rows, anonymous callers are denied, and tokens/write access remain restricted' as validation;
