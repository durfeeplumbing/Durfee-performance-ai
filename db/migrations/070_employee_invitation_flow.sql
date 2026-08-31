create table if not exists public.employee_invites(
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),
  email text not null,
  employee_name text not null,
  role text not null check(role in ('manager','csr_dispatch','technician','marketing','accounting')),
  expires_at timestamptz not null default (now()+interval '7 days'),
  used_at timestamptz,
  revoked_at timestamptz,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.employee_invites enable row level security;

create or replace function public.create_employee_invite_atomic(p_email text,p_name text,p_role text) returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare a public.users%rowtype;e public.users%rowtype;inv uuid;em text:=lower(btrim(coalesce(p_email,'')));nm text:=btrim(coalesce(p_name,''));begin
select * into a from public.users where auth_user_id=auth.uid() and active=true limit 1;if a.id is null or a.role not in ('owner','manager') or not private.has_permission('manage_team') then raise exception 'Permission denied';end if;if em='' or position('@' in em)<2 or length(em)>320 then raise exception 'Valid email required';end if;if nm='' or length(nm)>160 then raise exception 'Employee name required';end if;if p_role not in ('manager','csr_dispatch','technician','marketing','accounting') then raise exception 'Invalid employee role';end if;
select * into e from public.users where lower(email)=em for update;if found and e.auth_user_id is not null then raise exception 'Employee already has a linked login';end if;if found then update public.users set name=nm,role=p_role,active=true where id=e.id;else insert into public.users(email,name,role,active) values(em,nm,p_role,true) returning * into e;end if;
update public.employee_invites set revoked_at=now() where lower(email)=em and used_at is null and revoked_at is null;
insert into public.employee_invites(email,employee_name,role,created_by) values(em,nm,p_role,a.id) returning token into inv;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(a.id,'create_employee_invite','user',e.id::text,jsonb_build_object('email',em,'name',nm,'role',p_role,'invite_token_created',true));return inv;end$$;

create or replace function public.revoke_employee_invite_atomic(p_token uuid) returns boolean language plpgsql security definer set search_path=public,private,pg_temp as $$
declare a public.users%rowtype;i public.employee_invites%rowtype;begin select * into a from public.users where auth_user_id=auth.uid() and active=true limit 1;if a.id is null or a.role not in ('owner','manager') or not private.has_permission('manage_team') then raise exception 'Permission denied';end if;select * into i from public.employee_invites where token=p_token for update;if not found or i.used_at is not null or i.revoked_at is not null then raise exception 'Invite is no longer active';end if;update public.employee_invites set revoked_at=now() where id=i.id;insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(a.id,'revoke_employee_invite','employee_invite',i.id::text,jsonb_build_object('email',i.email,'role',i.role));return true;end$$;

create or replace function public.get_employee_invite(p_token uuid) returns table(email text,employee_name text,role text,expires_at timestamptz) language plpgsql security definer set search_path=public,pg_temp as $$begin return query select i.email,i.employee_name,i.role,i.expires_at from public.employee_invites i where i.token=p_token and i.used_at is null and i.revoked_at is null and i.expires_at>now();end$$;

create or replace function public.link_employee_auth_user() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  update public.users set auth_user_id=NEW.id where lower(email)=lower(NEW.email) and auth_user_id is null;
  update public.employee_invites set used_at=now() where lower(email)=lower(NEW.email) and used_at is null and revoked_at is null and expires_at>now();
  return NEW;
end$$;

revoke all on function public.create_employee_invite_atomic(text,text,text),public.revoke_employee_invite_atomic(uuid) from public,anon;
grant execute on function public.create_employee_invite_atomic(text,text,text),public.revoke_employee_invite_atomic(uuid) to authenticated;
revoke all on function public.get_employee_invite(uuid) from public,authenticated;
grant execute on function public.get_employee_invite(uuid) to anon;
revoke all on function public.link_employee_auth_user() from public,anon,authenticated;