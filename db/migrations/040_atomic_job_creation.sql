create or replace function public.create_job_atomic(
  p_customer_id uuid,
  p_service_type text,
  p_service_summary text default null,
  p_scheduled_start timestamptz default null,
  p_scheduled_end timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_role text;
  v_actor uuid;
  v_job_id uuid;
  v_status text;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('owner','manager','csr_dispatch') then raise exception 'Not authorized'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_customer_id is null or not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer required'; end if;
  if p_service_type is null or p_service_type not in ('Plumbing Service','Drain & Sewer','Water Heaters','Tankless','Boilers','Furnaces','Heat Pumps','Ductless Mini-Splits','Central AC','HVAC Service','HVAC Installation','Gas Piping','New Construction','IAQ') then raise exception 'Service type required'; end if;
  if p_scheduled_end is not null and p_scheduled_start is null then raise exception 'Schedule start required when schedule end is provided'; end if;
  if p_scheduled_start is not null and p_scheduled_end is not null and p_scheduled_end<=p_scheduled_start then raise exception 'Schedule end must be after start'; end if;
  if length(coalesce(p_service_summary,''))>5000 then raise exception 'Service summary is too long'; end if;
  v_status:=case when p_scheduled_start is null then 'booked' else 'scheduled' end;
  insert into public.jobs(customer_id,created_by,service_type,service_summary,status,scheduled_start,scheduled_end)
  values(p_customer_id,v_actor,p_service_type,nullif(btrim(coalesce(p_service_summary,'')),''),v_status,p_scheduled_start,p_scheduled_end)
  returning id into v_job_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(v_actor,'create_job','job',v_job_id::text,jsonb_build_object('customer_id',p_customer_id,'service_type',p_service_type,'status',v_status,'scheduled_start',p_scheduled_start,'scheduled_end',p_scheduled_end));
  return v_job_id;
end;
$$;
revoke all on function public.create_job_atomic(uuid,text,text,timestamptz,timestamptz) from public;
grant execute on function public.create_job_atomic(uuid,text,text,timestamptz,timestamptz) to authenticated;
