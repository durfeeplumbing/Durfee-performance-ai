create or replace function public.add_field_material_atomic(p_job_id uuid,p_sku text,p_description text,p_quantity numeric,p_unit_cost numeric default 0)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_role text;v_actor uuid;v_job public.jobs%rowtype;v_id uuid;begin
v_role:=private.current_employee_role();if v_role not in ('technician','owner','manager') then raise exception 'Not authorized';end if;
select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_actor is null then raise exception 'Employee identity unavailable';end if;
select * into v_job from public.jobs where id=p_job_id for update;if not found then raise exception 'Job not found';end if;
if v_role='technician' and v_job.technician_id is distinct from v_actor then raise exception 'Technicians can only update assigned jobs';end if;
if v_job.status<>'on_site' then raise exception 'Job must be on site before recording materials';end if;
if p_quantity is null or p_quantity<=0 then raise exception 'Quantity must be positive';end if;if coalesce(p_unit_cost,0)<0 then raise exception 'Unit cost cannot be negative';end if;
insert into public.material_usage(job_id,sku,description,quantity,unit_cost,source) values(p_job_id,coalesce(nullif(btrim(p_sku),''),'FIELD'),coalesce(nullif(btrim(p_description),''),'Field material'),p_quantity,coalesce(p_unit_cost,0),'field') returning id into v_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'add_field_material','material_usage',v_id::text,jsonb_build_object('job_id',p_job_id,'sku',coalesce(nullif(btrim(p_sku),''),'FIELD'),'quantity',p_quantity,'unit_cost',coalesce(p_unit_cost,0)));
return v_id;end;$$;
create or replace function public.add_job_note_atomic(p_job_id uuid,p_note_type text,p_note text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_role text;v_actor uuid;v_job public.jobs%rowtype;v_id uuid;begin
v_role:=private.current_employee_role();if v_role not in ('technician','owner','manager') then raise exception 'Not authorized';end if;
select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_actor is null then raise exception 'Employee identity unavailable';end if;
select * into v_job from public.jobs where id=p_job_id for update;if not found then raise exception 'Job not found';end if;
if v_role='technician' and v_job.technician_id is distinct from v_actor then raise exception 'Technicians can only update assigned jobs';end if;
if p_note_type not in ('work','diagnostic','customer','internal','completion') then raise exception 'Invalid note type';end if;if nullif(btrim(coalesce(p_note,'')),'') is null or length(p_note)>5000 then raise exception 'Enter a valid note';end if;
insert into public.job_notes(job_id,author_user_id,note_type,note) values(p_job_id,v_actor,p_note_type,btrim(p_note)) returning id into v_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'add_job_note','job_note',v_id::text,jsonb_build_object('job_id',p_job_id,'note_type',p_note_type));return v_id;end;$$;
revoke all on function public.add_field_material_atomic(uuid,text,text,numeric,numeric) from public;grant execute on function public.add_field_material_atomic(uuid,text,text,numeric,numeric) to authenticated;
revoke all on function public.add_job_note_atomic(uuid,text,text) from public;grant execute on function public.add_job_note_atomic(uuid,text,text) to authenticated;