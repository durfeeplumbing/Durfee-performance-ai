create table if not exists private.public_token_rate_limits (
  kind text not null,
  token uuid not null,
  window_started_at timestamptz not null default now(),
  hits integer not null default 0 check (hits >= 0),
  updated_at timestamptz not null default now(),
  primary key (kind, token)
);

revoke all on table private.public_token_rate_limits from public, anon, authenticated;

create or replace function private.consume_public_token_budget(
  p_kind text,
  p_token uuid,
  p_max_hits integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_hits integer;
begin
  if p_kind is null or p_kind = '' or p_token is null or p_max_hits < 1 or p_window_seconds < 1 then return false; end if;
  insert into private.public_token_rate_limits(kind, token, window_started_at, hits, updated_at)
  values (p_kind, p_token, now(), 1, now())
  on conflict (kind, token) do update set
    hits = case when private.public_token_rate_limits.window_started_at <= now() - make_interval(secs => p_window_seconds) then 1 else private.public_token_rate_limits.hits + 1 end,
    window_started_at = case when private.public_token_rate_limits.window_started_at <= now() - make_interval(secs => p_window_seconds) then now() else private.public_token_rate_limits.window_started_at end,
    updated_at = now()
  returning hits into v_hits;
  return v_hits <= p_max_hits;
end;
$$;

revoke all on function private.consume_public_token_budget(text, uuid, integer, integer) from public, anon, authenticated;

create or replace function public.get_employee_invite(p_token uuid)
returns table(email text, employee_name text, role text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare v_invite public.employee_invites%rowtype;
begin
  select * into v_invite from public.employee_invites i where i.token=p_token and i.used_at is null and i.revoked_at is null and i.expires_at>now();
  if not found then return; end if;
  if not private.consume_public_token_budget('employee_invite_view',p_token,60,900) then raise exception 'Too many invite requests. Try again later.'; end if;
  return query select v_invite.email,v_invite.employee_name,v_invite.role,v_invite.expires_at;
end;
$$;

create or replace function public.get_estimate_acceptance(p_token uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_link public.estimate_acceptance_links%rowtype; v_result jsonb;
begin
  select * into v_link from public.estimate_acceptance_links where token=p_token and revoked_at is null and used_at is null and expires_at>now();
  if not found then return null; end if;
  if not private.consume_public_token_budget('estimate_view',p_token,120,900) then raise exception 'Too many estimate requests. Try again later.'; end if;
  select jsonb_build_object(
    'estimate_id',e.id,'status',e.status,'customer_name',c.name,'service_address',c.service_address,
    'service_type',j.service_type,'service_summary',j.service_summary,'expires_at',v_link.expires_at,
    'options',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'tier',o.tier,'description',o.description,'price',o.price) order by case o.tier when 'Good' then 1 when 'Better' then 2 else 3 end) from public.estimate_options o where o.estimate_id=e.id),'[]'::jsonb)
  ) into v_result from public.estimates e join public.jobs j on j.id=e.job_id join public.customers c on c.id=j.customer_id where e.id=v_link.estimate_id and e.status<>'approved';
  return v_result;
end;
$$;

create or replace function public.accept_estimate(p_token uuid,p_option_id uuid,p_signer_name text,p_signature_text text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_link public.estimate_acceptance_links%rowtype; v_option public.estimate_options%rowtype; v_before jsonb;
  v_minimum_gp numeric; v_gp numeric; v_job_id uuid; v_job_status text;
begin
  if length(trim(coalesce(p_signer_name,''))) < 2 then raise exception 'Signer name required'; end if;
  if length(trim(coalesce(p_signer_name,''))) > 160 then raise exception 'Signer name is too long'; end if;
  if length(coalesce(p_signature_text,'')) > 500 then raise exception 'Signature text is too long'; end if;
  select * into v_link from public.estimate_acceptance_links where token=p_token and revoked_at is null and used_at is null and expires_at>now() for update;
  if not found then raise exception 'Approval link is invalid or expired'; end if;
  if not private.consume_public_token_budget('estimate_accept',p_token,10,900) then raise exception 'Too many approval attempts. Try again later.'; end if;
  select * into v_option from public.estimate_options where id=p_option_id and estimate_id=v_link.estimate_id;
  if not found then raise exception 'Estimate option not found'; end if;
  if coalesce(v_option.price,0)<=0 then raise exception 'Estimate option price is invalid'; end if;
  select minimum_gp into v_minimum_gp from public.company_pricing_settings where id=true;
  if v_minimum_gp is null or v_minimum_gp<0 or v_minimum_gp>=100 then raise exception 'Company pricing controls are unavailable or invalid'; end if;
  v_gp:=((v_option.price-coalesce(v_option.cost,0))/v_option.price)*100;
  if v_gp<v_minimum_gp then raise exception 'Selected option is below the company gross-profit floor and requires internal owner review'; end if;
  select to_jsonb(e),e.job_id into v_before,v_job_id from public.estimates e where e.id=v_link.estimate_id for update;
  if v_before is null then raise exception 'Estimate not found'; end if;
  if (v_before->>'status')='approved' then raise exception 'Estimate already approved'; end if;
  select status into v_job_status from public.jobs where id=v_job_id for update;
  if v_job_status is null then raise exception 'Job not found'; end if;
  if v_job_status in ('completed','closed','cancelled') then raise exception 'Job is no longer open for estimate approval'; end if;
  update public.estimates set status='approved',approved_option=v_option.tier,approved_option_id=v_option.id,approved_at=now(),customer_signed_name=trim(p_signer_name),customer_signed_at=now(),customer_signature_text=nullif(trim(coalesce(p_signature_text,'')),''),signature_reference='customer-link:'||v_link.id::text where id=v_link.estimate_id;
  update public.jobs set revenue=v_option.price where id=v_job_id;
  update public.estimate_acceptance_links set used_at=now() where id=v_link.id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(null,'customer_approved_estimate','estimate',v_link.estimate_id,v_before,jsonb_build_object('status','approved','job_id',v_job_id,'job_revenue',v_option.price,'approved_option_id',v_option.id,'approved_option',v_option.tier,'price',v_option.price,'cost',v_option.cost,'gp',v_gp,'minimum_gp',v_minimum_gp,'customer_signed_name',trim(p_signer_name),'customer_signed_at',now(),'acceptance_link_id',v_link.id));
  return true;
end;
$$;

revoke all on function public.get_employee_invite(uuid) from public, authenticated;
grant execute on function public.get_employee_invite(uuid) to anon;
revoke all on function public.get_estimate_acceptance(uuid) from public;
grant execute on function public.get_estimate_acceptance(uuid) to anon, authenticated;
revoke all on function public.accept_estimate(uuid,uuid,text,text) from public;
grant execute on function public.accept_estimate(uuid,uuid,text,text) to anon, authenticated;
