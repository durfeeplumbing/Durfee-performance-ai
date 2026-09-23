-- Store OAuth credentials without exposing the private schema through PostgREST.
-- The server is the only caller; encrypted token values are never returned.
grant usage on schema private to service_role;
-- Deliberately no end-user policies: only the server's service_role accesses tokens.
alter table private.marketing_provider_oauth_tokens enable row level security;

create or replace function public.marketing_provider_save_oauth(
  p_provider text,
  p_access_token_ciphertext text,
  p_refresh_token_ciphertext text default null,
  p_expires_at timestamptz default null,
  p_token_type text default 'Bearer',
  p_scopes text[] default '{}'
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if p_provider is null or p_provider not in ('google_ads', 'meta_ads') then
    raise exception 'Invalid provider';
  end if;
  if nullif(btrim(p_access_token_ciphertext), '') is null then
    raise exception 'Encrypted access token required';
  end if;

  insert into private.marketing_provider_oauth_tokens as stored (
    provider, access_token_ciphertext, refresh_token_ciphertext,
    expires_at, token_type, granted_scopes, updated_at
  ) values (
    p_provider, p_access_token_ciphertext, p_refresh_token_ciphertext,
    p_expires_at, coalesce(p_token_type, 'Bearer'), coalesce(p_scopes, '{}'), now()
  )
  on conflict (provider) do update set
    access_token_ciphertext = excluded.access_token_ciphertext,
    refresh_token_ciphertext = case
      when p_provider = 'google_ads' then
        coalesce(excluded.refresh_token_ciphertext, stored.refresh_token_ciphertext)
      else excluded.refresh_token_ciphertext
    end,
    expires_at = excluded.expires_at,
    token_type = excluded.token_type,
    granted_scopes = excluded.granted_scopes,
    updated_at = now();

  -- This runs in the same transaction: failed status updates roll back token saves.
  perform public.marketing_provider_mark_authorized(p_provider, p_scopes);
end;
$$;

revoke all on function public.marketing_provider_save_oauth(text,text,text,timestamptz,text,text[])
  from public, anon, authenticated;
grant execute on function public.marketing_provider_save_oauth(text,text,text,timestamptz,text,text[])
  to service_role;
notify pgrst, 'reload schema';
