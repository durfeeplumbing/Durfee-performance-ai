create or replace function public.create_estimate_atomic(p_job_id uuid)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_actor uuid;v_role text;v_job public.jobs%rowtype;v_id uuid;
begin
 select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true;
 if v_actor is null or v_role not in ('owner','manager','csr_dispatch','technician') then raise exception 'Not authorized';end if;
 select * into v_job from public.jobs where id=p_job_id for update;
 if not found then raise exception 'Job not found';end if;
 if v_role='technician' and v_job.technician_id is distinct from v_actor then raise exception 'Not authorized';end if;
 if v_job.status in ('completed','closed','cancelled') then raise exception 'This job is no longer open for a new estimate';end if;
 if exists(select 1 from public.estimates where job_id=p_job_id and status in ('draft','sent','approved')) then raise exception 'An active estimate already exists for this job';end if;
 insert into public.estimates(job_id,status) values(p_job_id,'draft') returning id into v_id;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'create_estimate','estimate',v_id::text,jsonb_build_object('job_id',p_job_id));
 return v_id;
end;$$;

create or replace function public.add_estimate_option_atomic(p_estimate_id uuid,p_tier text,p_description text,p_price numeric,p_cost numeric,p_price_book_tier_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_actor uuid;v_role text;v_estimate public.estimates%rowtype;v_job public.jobs%rowtype;v_floor numeric;v_allow boolean;v_gp numeric;v_id uuid;v_source_tier text;
begin
 select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true;
 if v_actor is null or v_role not in ('owner','manager','csr_dispatch','technician') then raise exception 'Not authorized';end if;
 if p_tier not in ('Good','Better','Best') or nullif(btrim(p_description),'') is null or p_price<=0 or p_cost<0 then raise exception 'Invalid option';end if;
 select * into v_estimate from public.estimates where id=p_estimate_id for update;if not found then raise exception 'Estimate not found';end if;
 if v_estimate.status='approved' then raise exception 'Approved estimates cannot be changed';end if;
 select * into v_job from public.jobs where id=v_estimate.job_id;if not found then raise exception 'Job not found';end if;
 if v_role='technician' and v_job.technician_id is distinct from v_actor then raise exception 'Not authorized';end if;
 if p_price_book_tier_id is not null then select tier into v_source_tier from public.price_book_tiers where id=p_price_book_tier_id and active=true;if v_source_tier is null or v_source_tier<>p_tier then raise exception 'Invalid price book package source';end if;end if;
 select minimum_gp,allow_owner_below_floor into v_floor,v_allow from public.company_pricing_settings where id=true;
 if v_floor is null or v_floor<0 or v_floor>=100 then raise exception 'Pricing controls unavailable or invalid';end if;
 v_gp:=((p_price-p_cost)/p_price)*100;if v_gp<v_floor and (v_role<>'owner' or not coalesce(v_allow,false)) then raise exception 'Option is below company GP floor';end if;
 insert into public.estimate_options(estimate_id,tier,description,price,cost,price_book_tier_id) values(p_estimate_id,p_tier,btrim(p_description),p_price,p_cost,p_price_book_tier_id) returning id into v_id;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'add_estimate_option','estimate_option',v_id::text,jsonb_build_object('estimate_id',p_estimate_id,'tier',p_tier,'price',p_price,'cost',p_cost,'gp',v_gp,'price_book_tier_id',p_price_book_tier_id));return v_id;
end;$$;

create or replace function public.create_estimate_acceptance_link_atomic(p_estimate_id uuid)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_actor uuid;v_role text;v_estimate public.estimates%rowtype;v_id uuid;v_now timestamptz:=now();
begin
 select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true;if v_actor is null or v_role not in ('owner','manager','csr_dispatch') then raise exception 'Not authorized';end if;
 select * into v_estimate from public.estimates where id=p_estimate_id for update;if not found or v_estimate.status='approved' then raise exception 'Estimate is not available for customer approval';end if;
 if not exists(select 1 from public.estimate_options where estimate_id=p_estimate_id) then raise exception 'Add at least one estimate option first';end if;
 update public.estimate_acceptance_links set revoked_at=v_now where estimate_id=p_estimate_id and used_at is null and revoked_at is null;
 insert into public.estimate_acceptance_links(estimate_id,created_by) values(p_estimate_id,v_actor) returning id into v_id;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'create_customer_approval_link','estimate',p_estimate_id::text,jsonb_build_object('link_id',v_id));return v_id;
end;$$;

create or replace function public.revoke_estimate_acceptance_link_atomic(p_link_id uuid)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_actor uuid;v_role text;v_estimate_id uuid;v_now timestamptz:=now();
begin
 select id,role into v_actor,v_role from public.users where auth_user_id=auth.uid() and active=true;if v_actor is null or v_role not in ('owner','manager','csr_dispatch') then raise exception 'Not authorized';end if;
 update public.estimate_acceptance_links set revoked_at=v_now where id=p_link_id and used_at is null and revoked_at is null returning estimate_id into v_estimate_id;
 if v_estimate_id is null then raise exception 'Approval link is already used, revoked, or unavailable';end if;
 insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'revoke_customer_approval_link','estimate',v_estimate_id::text,jsonb_build_object('link_id',p_link_id,'revoked_at',v_now));return v_estimate_id;
end;$$;

revoke all on function public.create_estimate_atomic(uuid) from public;grant execute on function public.create_estimate_atomic(uuid) to authenticated;
revoke all on function public.add_estimate_option_atomic(uuid,text,text,numeric,numeric,uuid) from public;grant execute on function public.add_estimate_option_atomic(uuid,text,text,numeric,numeric,uuid) to authenticated;
revoke all on function public.create_estimate_acceptance_link_atomic(uuid) from public;grant execute on function public.create_estimate_acceptance_link_atomic(uuid) to authenticated;
revoke all on function public.revoke_estimate_acceptance_link_atomic(uuid) from public;grant execute on function public.revoke_estimate_acceptance_link_atomic(uuid) to authenticated;
