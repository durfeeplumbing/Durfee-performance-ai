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
  v_minimum_gp numeric;
  v_gp numeric;
  v_job_id uuid;
  v_job_status text;
begin
  if length(trim(coalesce(p_signer_name,''))) < 2 then raise exception 'Signer name required'; end if;
  select * into v_link from public.estimate_acceptance_links where token=p_token and revoked_at is null and used_at is null and expires_at > now() for update;
  if not found then raise exception 'Approval link is invalid or expired'; end if;
  select * into v_option from public.estimate_options where id=p_option_id and estimate_id=v_link.estimate_id;
  if not found then raise exception 'Estimate option not found'; end if;
  if coalesce(v_option.price,0) <= 0 then raise exception 'Estimate option price is invalid'; end if;
  select minimum_gp into v_minimum_gp from public.company_pricing_settings where id=true;
  if v_minimum_gp is null or v_minimum_gp < 0 or v_minimum_gp >= 100 then raise exception 'Company pricing controls are unavailable or invalid'; end if;
  v_gp := ((v_option.price - coalesce(v_option.cost,0)) / v_option.price) * 100;
  if v_gp < v_minimum_gp then raise exception 'Selected option is below the company gross-profit floor and requires internal owner review'; end if;
  select to_jsonb(e),e.job_id into v_before,v_job_id from public.estimates e where e.id=v_link.estimate_id for update;
  if v_before is null then raise exception 'Estimate not found'; end if;
  if (v_before->>'status')='approved' then raise exception 'Estimate already approved'; end if;
  select status into v_job_status from public.jobs where id=v_job_id for update;
  if v_job_status is null then raise exception 'Job not found'; end if;
  if v_job_status in ('completed','closed','cancelled') then raise exception 'Job is no longer open for estimate approval'; end if;
  update public.estimates set status='approved',approved_option=v_option.tier,approved_option_id=v_option.id,approved_at=now(),customer_signed_name=trim(p_signer_name),customer_signed_at=now(),customer_signature_text=nullif(trim(coalesce(p_signature_text,'')),''),signature_reference='customer-link:'||v_link.id::text where id=v_link.estimate_id;
  update public.jobs set revenue=v_option.price where id=v_job_id;
  update public.estimate_acceptance_links set used_at=now() where id=v_link.id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(null,'customer_approved_estimate','estimate',v_link.estimate_id,v_before,jsonb_build_object('status','approved','job_id',v_job_id,'job_revenue',v_option.price,'approved_option_id',v_option.id,'approved_option',v_option.tier,'price',v_option.price,'cost',v_option.cost,'gp',v_gp,'minimum_gp',v_minimum_gp,'customer_signed_name',trim(p_signer_name),'customer_signed_at',now(),'acceptance_link_id',v_link.id));
  return true;
end;
$$;
revoke all on function public.accept_estimate(uuid,uuid,text,text) from public;
grant execute on function public.accept_estimate(uuid,uuid,text,text) to anon, authenticated;
