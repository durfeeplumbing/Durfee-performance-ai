create or replace function public.finalize_job_photo_atomic(
  p_job_id uuid,
  p_storage_path text,
  p_caption text default null
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_role text;
  v_actor uuid;
  v_job public.jobs%rowtype;
  v_id uuid;
  v_caption text;
begin
  v_role:=private.current_employee_role();
  if v_role not in ('technician','owner','manager') then raise exception 'Not authorized'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  select * into v_job from public.jobs where id=p_job_id for update;
  if not found then raise exception 'Job not found'; end if;
  if v_role='technician' and v_job.technician_id is distinct from v_actor then raise exception 'Technicians can only update assigned jobs'; end if;
  if nullif(btrim(coalesce(p_storage_path,'')),'') is null then raise exception 'Storage path required'; end if;
  if p_storage_path not like p_job_id::text || '/%' then raise exception 'Invalid job photo storage path'; end if;
  if length(p_storage_path)>1000 then raise exception 'Storage path is too long'; end if;
  v_caption:=nullif(btrim(coalesce(p_caption,'')),'');
  if length(coalesce(v_caption,''))>500 then raise exception 'Caption is too long'; end if;
  if exists(select 1 from public.job_attachments where storage_path=p_storage_path) then raise exception 'Photo is already recorded'; end if;
  insert into public.job_attachments(job_id,uploaded_by,attachment_type,storage_path,caption)
  values(p_job_id,v_actor,'photo',p_storage_path,v_caption)
  returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data)
  values(v_actor,'upload_job_photo','job_attachment',v_id::text,jsonb_build_object('job_id',p_job_id,'attachment_type','photo','storage_path',p_storage_path,'caption',v_caption));
  return v_id;
end;
$$;
revoke all on function public.finalize_job_photo_atomic(uuid,text,text) from public;
grant execute on function public.finalize_job_photo_atomic(uuid,text,text) to authenticated;