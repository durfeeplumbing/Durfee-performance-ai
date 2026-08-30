create or replace function public.create_job_invoice(p_job_id uuid,p_requested_total numeric)
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
  jsonb_build_object('job_id',p_job_id,'total',v_total,'gp',v_gp,'approved_estimate_id',v_estimate_id,'approved_option_id',v_option_id,'approved_total',v_approved_total,'owner_price_exception',v_exception));
  return v_invoice_id;
end;
$$;

create or replace function public.record_invoice_payment(p_invoice_id uuid,p_amount numeric,p_method text,p_reference text default null)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_role text;
  v_actor uuid;
  v_invoice public.invoices%rowtype;
  v_paid numeric;
  v_balance numeric;
  v_payment_id uuid;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','accounting') then raise exception 'Not authorized'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_amount is null or p_amount<=0 or p_method not in ('cash','check','card','ach','financing') then raise exception 'Valid payment required'; end if;
  select * into v_invoice from public.invoices where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_invoice.status<>'open' then raise exception 'Only open invoices can accept payments'; end if;
  select coalesce(sum(amount),0) into v_paid from public.payments where invoice_id=p_invoice_id;
  v_balance:=v_invoice.total-v_paid;
  if v_balance<=0.005 then raise exception 'Invoice has no remaining balance'; end if;
  if p_amount>v_balance+0.005 then raise exception 'Payment exceeds remaining balance'; end if;
  insert into public.payments(job_id,invoice_id,amount,method,reference) values(v_invoice.job_id,p_invoice_id,p_amount,p_method,nullif(trim(coalesce(p_reference,'')),'')) returning id into v_payment_id;
  if v_paid+p_amount>=v_invoice.total-0.005 then update public.invoices set status='paid' where id=p_invoice_id; end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(v_actor,'record_payment','payment',v_payment_id::text,jsonb_build_object('invoice_id',p_invoice_id,'amount',p_amount,'method',p_method,'balance_before',v_balance,'balance_after',greatest(0,v_balance-p_amount)));
  return v_payment_id;
end;
$$;

create or replace function public.close_job_financially(p_job_id uuid)
returns boolean
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
  v_billed numeric;
  v_paid numeric;
  v_cost numeric;
  v_gp numeric;
  v_completed timestamptz;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','accounting') then raise exception 'Not authorized'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_job.status<>'completed' then raise exception 'Job must be completed before financial closeout'; end if;
  if not exists(select 1 from public.invoices where job_id=p_job_id) then raise exception 'Invoice required'; end if;
  if exists(select 1 from public.invoices where job_id=p_job_id and status<>'paid') then raise exception 'Every invoice must be paid before financial closeout'; end if;
  select coalesce(sum(total),0) into v_billed from public.invoices where job_id=p_job_id;
  select coalesce(sum(amount),0) into v_paid from public.payments where job_id=p_job_id;
  if v_paid+0.005<v_billed or v_paid>v_billed+0.005 then raise exception 'Payment total does not reconcile with billed total'; end if;
  select minimum_gp,allow_owner_below_floor into v_min_gp,v_allow_owner from public.company_pricing_settings where id=true;
  if v_min_gp is null or v_min_gp<0 or v_min_gp>=100 then raise exception 'Company pricing controls are unavailable or invalid'; end if;
  v_cost:=coalesce(v_job.material_cost,0)+coalesce(v_job.labor_cost,0)+coalesce(v_job.allocated_overhead,0);
  v_gp:=case when v_billed>0 then ((v_billed-v_cost)/v_billed)*100 else 0 end;
  if v_gp<v_min_gp and not(v_role='owner' and coalesce(v_allow_owner,false)) then raise exception 'Below-floor closeout requires authorized owner override'; end if;
  v_completed:=coalesce(v_job.completed_at,now());
  update public.jobs set status='closed',revenue=v_billed,completed_at=v_completed where id=p_job_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(v_actor,'close_job','job',p_job_id::text,jsonb_build_object('billed',v_billed,'paid',v_paid,'gp',v_gp,'completed_at',v_completed));
  return true;
end;
$$;

revoke all on function public.create_job_invoice(uuid,numeric) from public;
revoke all on function public.record_invoice_payment(uuid,numeric,text,text) from public;
revoke all on function public.close_job_financially(uuid) from public;
grant execute on function public.create_job_invoice(uuid,numeric) to authenticated;
grant execute on function public.record_invoice_payment(uuid,numeric,text,text) to authenticated;
grant execute on function public.close_job_financially(uuid) to authenticated;
