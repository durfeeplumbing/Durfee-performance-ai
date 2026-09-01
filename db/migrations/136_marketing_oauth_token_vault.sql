create table if not exists private.marketing_provider_oauth_tokens (
  provider text primary key check (provider in ('google_ads','meta_ads')),
  access_token_ciphertext text not null,
  refresh_token_ciphertext text,
  expires_at timestamptz,
  token_type text,
  granted_scopes text[] not null default '{}',
  updated_at timestamptz not null default now()
);
revoke all on private.marketing_provider_oauth_tokens from public,anon,authenticated;
grant select,insert,update,delete on private.marketing_provider_oauth_tokens to service_role;

create or replace function public.marketing_provider_mark_authorized(p_provider text,p_scopes text[] default '{}')
returns void language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_provider not in ('google_ads','meta_ads') then raise exception 'Invalid provider'; end if;
  insert into public.marketing_provider_connections(provider,connection_status,granted_scopes,authorized_at,last_error,updated_at)
  values(p_provider,'authorized',coalesce(p_scopes,'{}'),now(),null,now())
  on conflict(provider) do update set connection_status='authorized',granted_scopes=excluded.granted_scopes,authorized_at=now(),last_error=null,updated_at=now();
end$$;
revoke all on function public.marketing_provider_mark_authorized(text,text[]) from public,anon,authenticated;
grant execute on function public.marketing_provider_mark_authorized(text,text[]) to service_role;

create or replace function public.marketing_provider_disconnect(p_provider text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_provider not in ('google_ads','meta_ads') then raise exception 'Invalid provider'; end if;
  delete from private.marketing_provider_oauth_tokens where provider=p_provider;
  update public.marketing_provider_connections set connection_status='authorization_required',external_account_id=null,account_name=null,granted_scopes='{}',authorized_at=null,last_synced_at=null,last_error=null,updated_at=now() where provider=p_provider;
  update public.marketing_conversion_sync_queue set status='waiting_authorization',updated_at=now() where provider=p_provider and status in ('ready','failed','processing');
end$$;
revoke all on function public.marketing_provider_disconnect(text) from public,anon,authenticated;
grant execute on function public.marketing_provider_disconnect(text) to service_role;
