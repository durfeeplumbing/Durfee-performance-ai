create or replace function public.create_job_invoice_explicit(p_job_id uuid,p_requested_total numeric,p_owner_price_exception boolean default false)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_role text;
  v_actor uuid;
  v_job public.jobs%rowtype;
  v_min_gp numeric;
  v_allow_owner boolean;
  v_estimate_id uuid;
  v_option_id uuid;
  v_approved_total numeric;
  v_total numeric;
  v_cost numeric;
  v_gp numeric;
  v_exception boolean:=false;
  v_invoice_id uuid;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','accounting') then raise exception 'Not authorized'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.status<>'completed' then raise exception 'Only completed jobs can be invoiced'; end if;
  if exists(select 1 from public.invoices where job_id=p_job_id and status in ('open','paid')) then raise exception 'An active invoice already exists for this job'; end if;
  select minimum_gp,allow_owner_below_floor into v_min_gp,v_allow_owner from public.company_pricing_settings where id=true;
  if v_min_gp is null or v_min_gp<0 or v_min_gp>=100 then raise exception 'Company pricing controls are unavailable or invalid'; end if;
  select e.id,e.approved_option_id,o.price into v_estimate_id,v_option_id,v_approved_total
  from public.estimates e join public.estimate_options o on o.id=e.approved_option_id
  where e.job_id=p_job_id and e.status='approved' order by e.approved_at desc nulls last limit 1;
  v_total:=p_requested_total;
  if v_total is null or v_total<=0 then v_total:=v_job.revenue; end if;
  if v_total is null or v_total<=0 then raise exception 'Invoice total required'; end if;
  if v_estimate_id is not null and abs(v_total-v_approved_total)>0.005 then
    if v_role<>'owner' then raise exception 'Invoice must match approved estimate price'; end if;
    if not coalesce(p_owner_price_exception,false) then raise exception 'Owner price exception acknowledgement required'; end if;
    v_exception:=true;
  elsif v_estimate_id is not null then
    v_total:=v_approved_total;
  end if;
  v_cost:=coalesce(v_job.material_cost,0)+coalesce(v_job.labor_cost,0)+coalesce(v_job.allocated_overhead,0);
  v_gp:=((v_total-v_cost)/v_total)*100;
  if v_gp<v_min_gp and not(v_role='owner' and coalesce(v_allow_owner,false)) then raise exception 'Invoice is below the company GP floor'; end if;
  insert into public.invoices(job_id,status,subtotal,tax,total) values(p_job_id,'open',v_total,0,v_total) returning id into v_invoice_id;
  update public.jobs set revenue=v_total where id=p_job_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(v_actor,case when v_exception then 'create_invoice_owner_price_exception' else 'create_invoice' end,'invoice',v_invoice_id::text,
  jsonb_build_object('job_id',p_job_id,'total',v_total,'gp',v_gp,'approved_estimate_id',v_estimate_id,'approved_option_id',v_option_id,'approved_total',v_approved_total,'owner_price_exception',v_exception,'owner_exception_acknowledged',coalesce(p_owner_price_exception,false)));
  return v_invoice_id;
end;
$$;
revoke all on function public.create_job_invoice_explicit(uuid,numeric,boolean) from public;
grant execute on function public.create_job_invoice_explicit(uuid,numeric,boolean) to authenticated;
