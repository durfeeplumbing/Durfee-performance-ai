create or replace function private.audit_company_pricing_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values (new.updated_by,'update_pricing_settings','company_pricing_settings',null,to_jsonb(old),to_jsonb(new));
  return new;
end;
$$;

revoke all on function private.audit_company_pricing_change() from public, anon, authenticated;

drop trigger if exists audit_company_pricing_change on public.company_pricing_settings;
create trigger audit_company_pricing_change
after update on public.company_pricing_settings
for each row execute function private.audit_company_pricing_change();
