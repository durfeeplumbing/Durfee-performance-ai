alter function public.add_customer_equipment_atomic_impl(uuid,text,text,text,text,text,date,date,date,date,text) set schema private;
alter function public.create_customer_atomic_impl(text,text,text,text,numeric,numeric) set schema private;
alter function public.save_technician_skill_atomic_impl(uuid,text,integer,boolean,text,date) set schema private;
alter function public.update_customer_verified_address_atomic_impl(uuid,text,numeric,numeric) set schema private;
alter function public.create_employee_invite_atomic(text,text,text) set schema private;
alter function public.revoke_employee_invite_atomic(uuid) set schema private;

create or replace function public.add_customer_equipment_atomic(p_customer_id uuid,p_equipment_type text,p_manufacturer text,p_model_number text,p_serial_number text,p_location text,p_installed_on date,p_warranty_expires_on date,p_last_service_on date,p_next_maintenance_on date,p_notes text) returns uuid language plpgsql security invoker set search_path='' as $$begin if not (private.has_permission('manage_customers') or private.has_permission('field_app')) then raise exception 'Permission denied'; end if; return private.add_customer_equipment_atomic_impl(p_customer_id,p_equipment_type,p_manufacturer,p_model_number,p_serial_number,p_location,p_installed_on,p_warranty_expires_on,p_last_service_on,p_next_maintenance_on,p_notes); end$$;
create or replace function public.create_customer_atomic(p_name text,p_phone text,p_email text,p_service_address text,p_latitude numeric,p_longitude numeric) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_customers') then raise exception 'Permission denied'; end if; return private.create_customer_atomic_impl(p_name,p_phone,p_email,p_service_address,p_latitude,p_longitude); end$$;
create or replace function public.save_technician_skill_atomic(p_technician_id uuid,p_skill text,p_proficiency integer,p_certified boolean,p_certification_name text,p_certification_expires_on date) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_team') then raise exception 'Permission denied'; end if; return private.save_technician_skill_atomic_impl(p_technician_id,p_skill,p_proficiency,p_certified,p_certification_name,p_certification_expires_on); end$$;
create or replace function public.update_customer_verified_address_atomic(p_customer_id uuid,p_service_address text,p_latitude numeric,p_longitude numeric) returns uuid language plpgsql security invoker set search_path='' as $$begin if not private.has_permission('manage_customers') then raise exception 'Permission denied'; end if; return private.update_customer_verified_address_atomic_impl(p_customer_id,p_service_address,p_latitude,p_longitude); end$$;
create or replace function public.create_employee_invite_atomic(p_email text,p_name text,p_role text) returns uuid language sql security invoker set search_path='' as $$select private.create_employee_invite_atomic(p_email,p_name,p_role)$$;
create or replace function public.revoke_employee_invite_atomic(p_token uuid) returns boolean language sql security invoker set search_path='' as $$select private.revoke_employee_invite_atomic(p_token)$$;

revoke all on function private.add_customer_equipment_atomic_impl(uuid,text,text,text,text,text,date,date,date,date,text) from public,anon,authenticated;
revoke all on function private.create_customer_atomic_impl(text,text,text,text,numeric,numeric) from public,anon,authenticated;
revoke all on function private.save_technician_skill_atomic_impl(uuid,text,integer,boolean,text,date) from public,anon,authenticated;
revoke all on function private.update_customer_verified_address_atomic_impl(uuid,text,numeric,numeric) from public,anon,authenticated;
revoke all on function private.create_employee_invite_atomic(text,text,text) from public,anon,authenticated;
revoke all on function private.revoke_employee_invite_atomic(uuid) from public,anon,authenticated;

grant execute on function public.add_customer_equipment_atomic(uuid,text,text,text,text,text,date,date,date,date,text) to authenticated;
grant execute on function public.create_customer_atomic(text,text,text,text,numeric,numeric) to authenticated;
grant execute on function public.save_technician_skill_atomic(uuid,text,integer,boolean,text,date) to authenticated;
grant execute on function public.update_customer_verified_address_atomic(uuid,text,numeric,numeric) to authenticated;
grant execute on function public.create_employee_invite_atomic(text,text,text) to authenticated;
grant execute on function public.revoke_employee_invite_atomic(uuid) to authenticated;
