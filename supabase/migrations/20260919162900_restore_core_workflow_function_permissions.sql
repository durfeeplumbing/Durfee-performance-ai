-- Restore the caller-to-private-function chain without elevating the public RPCs.
-- Each private implementation repeats the permission check before accepting calls.
CREATE OR REPLACE FUNCTION private.close_job_financially_impl(p_job_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
  if auth.uid() is null or not coalesce(private.has_permission('manage_billing'), false) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  v_role:=private.current_employee_role();
  
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
$function$;
revoke all on function private.close_job_financially_impl(uuid) from public, anon;
grant execute on function private.close_job_financially_impl(uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.create_customer_atomic_impl(p_name text, p_phone text, p_email text, p_service_address text, p_latitude numeric, p_longitude numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_role text;v_actor uuid;v_id uuid;begin
  if auth.uid() is null or not coalesce(private.has_permission('manage_customers'), false) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
v_role:=private.current_employee_role();select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_actor is null then raise exception 'Employee identity unavailable';end if;
if nullif(btrim(coalesce(p_name,'')),'') is null then raise exception 'Customer name is required';end if;if nullif(btrim(coalesce(p_service_address,'')),'') is null or p_latitude is null or p_longitude is null then raise exception 'Verified service address and coordinates are required';end if;if p_latitude<-90 or p_latitude>90 or p_longitude<-180 or p_longitude>180 then raise exception 'Invalid customer coordinates';end if;
insert into public.customers(name,phone,email,service_address,latitude,longitude) values(btrim(p_name),nullif(btrim(coalesce(p_phone,'')),''),nullif(btrim(coalesce(p_email,'')),''),btrim(p_service_address),p_latitude,p_longitude) returning id into v_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'create_customer','customer',v_id::text,jsonb_build_object('name',btrim(p_name),'phone',nullif(btrim(coalesce(p_phone,'')),''),'email',nullif(btrim(coalesce(p_email,'')),''),'service_address',btrim(p_service_address),'latitude',p_latitude,'longitude',p_longitude,'verified_address',true));return v_id;end;$function$;
revoke all on function private.create_customer_atomic_impl(text,text,text,text,numeric,numeric) from public, anon;
grant execute on function private.create_customer_atomic_impl(text,text,text,text,numeric,numeric) to authenticated;

CREATE OR REPLACE FUNCTION private.create_job_invoice_explicit_impl(p_job_id uuid, p_requested_total numeric, p_owner_price_exception boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
  if auth.uid() is null or not coalesce(private.has_permission('manage_billing'), false) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  v_role:=private.current_employee_role();
  
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
$function$;
revoke all on function private.create_job_invoice_explicit_impl(uuid,numeric,boolean) from public, anon;
grant execute on function private.create_job_invoice_explicit_impl(uuid,numeric,boolean) to authenticated;

CREATE OR REPLACE FUNCTION private.record_invoice_payment_impl(p_invoice_id uuid, p_amount numeric, p_method text, p_reference text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_role text;
  v_actor uuid;
  v_invoice public.invoices%rowtype;
  v_paid numeric;
  v_balance numeric;
  v_payment_id uuid;
begin
  if auth.uid() is null or not coalesce(private.has_permission('manage_billing'), false) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  v_role:=private.current_employee_role();
  
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
$function$;
revoke all on function private.record_invoice_payment_impl(uuid,numeric,text,text) from public, anon;
grant execute on function private.record_invoice_payment_impl(uuid,numeric,text,text) to authenticated;

CREATE OR REPLACE FUNCTION private.create_employee_invite_atomic(p_email text, p_name text, p_role text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$ declare a public.users%rowtype;e public.users%rowtype;inv uuid;em text:=lower(btrim(coalesce(p_email,'')));nm text:=btrim(coalesce(p_name,''));begin
  if auth.uid() is null or not coalesce(private.has_permission('manage_team'), false) then
    raise exception 'Permission denied' using errcode = '42501';
  end if; select * into a from public.users where auth_user_id=auth.uid() and active=true limit 1;if a.id is null then raise exception 'Employee identity unavailable'; end if; if not private.has_permission('manage_team') then raise exception 'Permission denied'; end if;if em='' or position('@' in em)<2 or length(em)>320 then raise exception 'Valid email required';end if;if nm='' or length(nm)>160 then raise exception 'Employee name required';end if;if p_role not in ('manager','csr_dispatch','technician','marketing','accounting') then raise exception 'Invalid employee role';end if;select * into e from public.users where lower(email)=em for update;if found and e.auth_user_id is not null then raise exception 'Employee already has a linked login';end if;if found then update public.users set name=nm,role=p_role,active=true where id=e.id;else insert into public.users(email,name,role,active) values(em,nm,p_role,true) returning * into e;end if;update public.employee_invites set revoked_at=now() where lower(email)=em and used_at is null and revoked_at is null;insert into public.employee_invites(email,employee_name,role,created_by) values(em,nm,p_role,a.id) returning token into inv;insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(a.id,'create_employee_invite','user',e.id::text,jsonb_build_object('email',em,'name',nm,'role',p_role,'invite_token_created',true));return inv;end$function$;
revoke all on function private.create_employee_invite_atomic(text,text,text) from public, anon;
grant execute on function private.create_employee_invite_atomic(text,text,text) to authenticated;

CREATE OR REPLACE FUNCTION private.revoke_employee_invite_atomic(p_token uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$ declare a public.users%rowtype;i public.employee_invites%rowtype;begin
  if auth.uid() is null or not coalesce(private.has_permission('manage_team'), false) then
    raise exception 'Permission denied' using errcode = '42501';
  end if; select * into a from public.users where auth_user_id=auth.uid() and active=true limit 1;if a.id is null then raise exception 'Employee identity unavailable'; end if; if not private.has_permission('manage_team') then raise exception 'Permission denied'; end if;select * into i from public.employee_invites where token=p_token for update;if not found or i.used_at is not null or i.revoked_at is not null then raise exception 'Invite is no longer active';end if;update public.employee_invites set revoked_at=now() where id=i.id;insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(a.id,'revoke_employee_invite','employee_invite',i.id::text,jsonb_build_object('email',i.email,'role',i.role));return true;end$function$;
revoke all on function private.revoke_employee_invite_atomic(uuid) from public, anon;
grant execute on function private.revoke_employee_invite_atomic(uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.save_technician_skill_atomic_impl(p_technician_id uuid, p_skill text, p_proficiency integer, p_certified boolean, p_certification_name text, p_certification_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare actor public.users%rowtype;tech public.users%rowtype;old_skill public.technician_skills%rowtype;saved_id uuid;allowed text[]:=array['Plumbing Service','Drain & Sewer','Water Heaters','Tankless','Boilers','Furnaces','Heat Pumps','Ductless Mini-Splits','Central AC','HVAC Service','HVAC Installation','Gas Piping','New Construction','IAQ'];begin
  if auth.uid() is null or not coalesce(private.has_permission('manage_team'), false) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
select * into actor from public.users where auth_user_id=auth.uid() and active=true limit 1;if actor.id is null then raise exception 'Employee identity unavailable'; end if;
if p_technician_id is null or not (p_skill=any(allowed)) or p_proficiency is null or p_proficiency<0 or p_proficiency>100 then raise exception 'Invalid technician skill';end if;
select * into tech from public.users where id=p_technician_id for update;if not found or tech.role<>'technician' or tech.active<>true then raise exception 'Active technician required';end if;
if coalesce(p_certified,false)=false and (nullif(btrim(coalesce(p_certification_name,'')),'') is not null or p_certification_expires_on is not null) then raise exception 'Certification details require Certified to be selected';end if;
select * into old_skill from public.technician_skills where technician_id=p_technician_id and skill=p_skill for update;
insert into public.technician_skills(technician_id,skill,proficiency,certified,certification_name,certification_expires_on,active) values(p_technician_id,p_skill,p_proficiency,coalesce(p_certified,false),case when coalesce(p_certified,false) then nullif(btrim(coalesce(p_certification_name,'')),'') else null end,case when coalesce(p_certified,false) then p_certification_expires_on else null end,true)
on conflict(technician_id,skill) do update set proficiency=excluded.proficiency,certified=excluded.certified,certification_name=excluded.certification_name,certification_expires_on=excluded.certification_expires_on,active=true returning id into saved_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(actor.id,'save_technician_skill','technician_skill',saved_id::text,case when old_skill.id is null then null else to_jsonb(old_skill) end,jsonb_build_object('technician_id',p_technician_id,'skill',p_skill,'proficiency',p_proficiency,'certified',coalesce(p_certified,false),'certification_name',case when coalesce(p_certified,false) then nullif(btrim(coalesce(p_certification_name,'')),'') else null end,'certification_expires_on',case when coalesce(p_certified,false) then p_certification_expires_on else null end,'active',true));return saved_id;end;$function$;
revoke all on function private.save_technician_skill_atomic_impl(uuid,text,integer,boolean,text,date) from public, anon;
grant execute on function private.save_technician_skill_atomic_impl(uuid,text,integer,boolean,text,date) to authenticated;


