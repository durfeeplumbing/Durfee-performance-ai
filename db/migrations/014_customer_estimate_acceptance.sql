alter table public.estimates
  add column if not exists customer_signed_name text,
  add column if not exists customer_signed_at timestamptz,
  add column if not exists customer_signature_text text;

create table if not exists public.estimate_acceptance_links (
  id uuid primary key default gen_random_uuid(),
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  token uuid not null unique default gen_random_uuid(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  revoked_at timestamptz,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now()
);
create index if not exists estimate_acceptance_links_estimate_idx on public.estimate_acceptance_links(estimate_id);
create index if not exists estimate_acceptance_links_token_idx on public.estimate_acceptance_links(token);
alter table public.estimate_acceptance_links enable row level security;

drop policy if exists "ops read estimate acceptance links" on public.estimate_acceptance_links;
create policy "ops read estimate acceptance links" on public.estimate_acceptance_links
for select to authenticated using (private.current_employee_role() in ('owner','manager','csr_dispatch'));

drop policy if exists "ops create estimate acceptance links" on public.estimate_acceptance_links;
create policy "ops create estimate acceptance links" on public.estimate_acceptance_links
for insert to authenticated with check (
  private.current_employee_role() in ('owner','manager','csr_dispatch')
  and created_by = (select id from public.users where auth_user_id=auth.uid() limit 1)
);

drop policy if exists "ops update estimate acceptance links" on public.estimate_acceptance_links;
create policy "ops update estimate acceptance links" on public.estimate_acceptance_links
for update to authenticated using (private.current_employee_role() in ('owner','manager','csr_dispatch'))
with check (private.current_employee_role() in ('owner','manager','csr_dispatch'));

create or replace function public.get_estimate_acceptance(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_link public.estimate_acceptance_links%rowtype;
  v_result jsonb;
begin
  select * into v_link from public.estimate_acceptance_links
  where token=p_token and revoked_at is null and used_at is null and expires_at > now();
  if not found then return null; end if;

  select jsonb_build_object(
    'estimate_id',e.id,
    'status',e.status,
    'customer_name',c.name,
    'service_address',c.service_address,
    'service_type',j.service_type,
    'service_summary',j.service_summary,
    'expires_at',v_link.expires_at,
    'options',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'tier',o.tier,'description',o.description,'price',o.price) order by case o.tier when 'Good' then 1 when 'Better' then 2 else 3 end) from public.estimate_options o where o.estimate_id=e.id),'[]'::jsonb)
  ) into v_result
  from public.estimates e
  join public.jobs j on j.id=e.job_id
  join public.customers c on c.id=j.customer_id
  where e.id=v_link.estimate_id and e.status <> 'approved';
  return v_result;
end;
$$;

revoke all on function public.get_estimate_acceptance(uuid) from public;
grant execute on function public.get_estimate_acceptance(uuid) to anon, authenticated;

create or replace function public.accept_estimate(
  p_token uuid,
  p_option_id uuid,
  p_signer_name text,
  p_signature_text text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_link public.estimate_acceptance_links%rowtype;
  v_option public.estimate_options%rowtype;
  v_before jsonb;
begin
  if length(trim(coalesce(p_signer_name,''))) < 2 then raise exception 'Signer name required'; end if;
  select * into v_link from public.estimate_acceptance_links
  where token=p_token and revoked_at is null and used_at is null and expires_at > now()
  for update;
  if not found then raise exception 'Approval link is invalid or expired'; end if;

  select * into v_option from public.estimate_options
  where id=p_option_id and estimate_id=v_link.estimate_id;
  if not found then raise exception 'Estimate option not found'; end if;

  select to_jsonb(e) into v_before from public.estimates e where e.id=v_link.estimate_id for update;
  if (v_before->>'status')='approved' then raise exception 'Estimate already approved'; end if;

  update public.estimates set
    status='approved',
    approved_option=v_option.tier,
    approved_option_id=v_option.id,
    approved_at=now(),
    customer_signed_name=trim(p_signer_name),
    customer_signed_at=now(),
    customer_signature_text=nullif(trim(coalesce(p_signature_text,'')),''),
    signature_reference='customer-link:'||v_link.id::text
  where id=v_link.estimate_id;

  update public.estimate_acceptance_links set used_at=now() where id=v_link.id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(null,'customer_approved_estimate','estimate',v_link.estimate_id,v_before,
    jsonb_build_object('status','approved','approved_option_id',v_option.id,'approved_option',v_option.tier,'customer_signed_name',trim(p_signer_name),'customer_signed_at',now(),'acceptance_link_id',v_link.id));
  return true;
end;
$$;

revoke all on function public.accept_estimate(uuid,uuid,text,text) from public;
grant execute on function public.accept_estimate(uuid,uuid,text,text) to anon, authenticated;
