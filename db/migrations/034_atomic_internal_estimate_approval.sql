create or replace function public.approve_estimate_option_internal(
  p_estimate_id uuid,
  p_option_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_actor uuid;
  v_role text;
  v_estimate public.estimates%rowtype;
  v_option public.estimate_options%rowtype;
  v_minimum_gp numeric;
  v_allow_owner_below_floor boolean;
  v_gp numeric;
  v_now timestamptz := now();
begin
  select u.id, u.role into v_actor, v_role
  from public.users u
  where u.auth_user_id = auth.uid()
    and u.active = true;

  if v_actor is null or v_role not in ('owner','manager','csr_dispatch') then
    raise exception 'Not authorized';
  end if;

  select * into v_estimate
  from public.estimates
  where id = p_estimate_id
  for update;

  if not found or v_estimate.status = 'approved' then
    raise exception 'Estimate is no longer available for approval';
  end if;

  select * into v_option
  from public.estimate_options
  where id = p_option_id
    and estimate_id = p_estimate_id;

  if not found or v_option.price is null or v_option.price <= 0 then
    raise exception 'Option not found or invalid';
  end if;

  select minimum_gp, allow_owner_below_floor
    into v_minimum_gp, v_allow_owner_below_floor
  from public.company_pricing_settings
  where id = true;

  if v_minimum_gp is null or v_minimum_gp < 0 or v_minimum_gp >= 100 then
    raise exception 'Company pricing controls are unavailable or invalid';
  end if;

  v_gp := ((v_option.price - v_option.cost) / v_option.price) * 100;
  if v_gp < v_minimum_gp and (v_role <> 'owner' or not coalesce(v_allow_owner_below_floor,false)) then
    raise exception 'Below-floor approval requires authorized owner override';
  end if;

  if exists (
    select 1 from public.jobs j
    where j.id = v_estimate.job_id
      and j.status in ('completed','closed','cancelled')
  ) then
    raise exception 'Job is no longer eligible for estimate approval';
  end if;

  update public.estimates
  set status = 'approved',
      approved_option = v_option.tier,
      approved_option_id = v_option.id,
      approved_at = v_now,
      signature_reference = 'employee-approved:' || v_actor::text
  where id = p_estimate_id;

  update public.jobs
  set revenue = v_option.price
  where id = v_estimate.job_id;

  if not found then
    raise exception 'Job revenue could not be synchronized';
  end if;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values (
    v_actor,
    'approve_estimate_option',
    'estimate',
    p_estimate_id::text,
    jsonb_build_object(
      'job_id',v_estimate.job_id,
      'option_id',v_option.id,
      'tier',v_option.tier,
      'price',v_option.price,
      'gp',v_gp,
      'minimum_gp',v_minimum_gp,
      'approved_at',v_now,
      'approval_source','internal',
      'job_revenue_synchronized',true
    )
  );

  return p_estimate_id;
end;
$$;

revoke all on function public.approve_estimate_option_internal(uuid,uuid) from public;
grant execute on function public.approve_estimate_option_internal(uuid,uuid) to authenticated;
