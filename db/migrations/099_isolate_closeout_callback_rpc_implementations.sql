-- Isolate GP/zero-dollar closeout and callback review implementations from the exposed schema.
alter function public.approve_gp_closeout(uuid,text) set schema private;
alter function public.reject_gp_closeout(uuid,text) set schema private;
alter function public.request_gp_closeout_approval(uuid) set schema private;
alter function public.gp_closeout_queue() set schema private;
alter function public.approve_zero_invoice_closeout(uuid,text) set schema private;
alter function public.reject_zero_invoice_closeout(uuid,text) set schema private;
alter function public.request_zero_invoice_closeout_approval(uuid) set schema private;
alter function public.zero_invoice_closeout_queue() set schema private;
alter function public.record_job_callback(uuid,uuid,text,text) set schema private;
alter function public.review_job_callback(uuid,text,numeric,text) set schema private;
alter function public.job_callback_management_queue() set schema private;
alter function public.technician_callback_snapshot(integer) set schema private;
alter function public.field_closeout_economics() set schema private;

grant usage on schema private to authenticated;
grant execute on function private.approve_gp_closeout(uuid,text),private.reject_gp_closeout(uuid,text),private.request_gp_closeout_approval(uuid),private.gp_closeout_queue(),private.approve_zero_invoice_closeout(uuid,text),private.reject_zero_invoice_closeout(uuid,text),private.request_zero_invoice_closeout_approval(uuid),private.zero_invoice_closeout_queue(),private.record_job_callback(uuid,uuid,text,text),private.review_job_callback(uuid,text,numeric,text),private.job_callback_management_queue(),private.technician_callback_snapshot(integer),private.field_closeout_economics() to authenticated;

create function public.approve_gp_closeout(p_job_id uuid,p_manager_note text default null) returns uuid language sql security invoker set search_path='' as $$select private.approve_gp_closeout($1,$2)$$;
create function public.reject_gp_closeout(p_job_id uuid,p_manager_note text default null) returns uuid language sql security invoker set search_path='' as $$select private.reject_gp_closeout($1,$2)$$;
create function public.request_gp_closeout_approval(p_job_id uuid) returns uuid language sql security invoker set search_path='' as $$select private.request_gp_closeout_approval($1)$$;
create function public.gp_closeout_queue() returns jsonb language sql stable security invoker set search_path='' as $$select private.gp_closeout_queue()$$;
create function public.approve_zero_invoice_closeout(p_job_id uuid,p_manager_note text default null) returns uuid language sql security invoker set search_path='' as $$select private.approve_zero_invoice_closeout($1,$2)$$;
create function public.reject_zero_invoice_closeout(p_job_id uuid,p_manager_note text default null) returns uuid language sql security invoker set search_path='' as $$select private.reject_zero_invoice_closeout($1,$2)$$;
create function public.request_zero_invoice_closeout_approval(p_job_id uuid) returns uuid language sql security invoker set search_path='' as $$select private.request_zero_invoice_closeout_approval($1)$$;
create function public.zero_invoice_closeout_queue() returns jsonb language sql stable security invoker set search_path='' as $$select private.zero_invoice_closeout_queue()$$;
create function public.record_job_callback(p_original_job_id uuid,p_callback_job_id uuid,p_reason text default 'unknown',p_manager_note text default null) returns uuid language sql security invoker set search_path='' as $$select private.record_job_callback($1,$2,$3,$4)$$;
create function public.review_job_callback(p_callback_id uuid,p_preventability text,p_callback_cost numeric default 0,p_manager_note text default null) returns uuid language sql security invoker set search_path='' as $$select private.review_job_callback($1,$2,$3,$4)$$;
create function public.job_callback_management_queue() returns jsonb language sql stable security invoker set search_path='' as $$select private.job_callback_management_queue()$$;
create function public.technician_callback_snapshot(p_days integer default 30) returns jsonb language sql stable security invoker set search_path='' as $$select private.technician_callback_snapshot($1)$$;
create function public.field_closeout_economics() returns jsonb language sql stable security invoker set search_path='' as $$select private.field_closeout_economics()$$;

revoke all on function public.approve_gp_closeout(uuid,text),public.reject_gp_closeout(uuid,text),public.request_gp_closeout_approval(uuid),public.gp_closeout_queue(),public.approve_zero_invoice_closeout(uuid,text),public.reject_zero_invoice_closeout(uuid,text),public.request_zero_invoice_closeout_approval(uuid),public.zero_invoice_closeout_queue(),public.record_job_callback(uuid,uuid,text,text),public.review_job_callback(uuid,text,numeric,text),public.job_callback_management_queue(),public.technician_callback_snapshot(integer),public.field_closeout_economics() from public,anon;
grant execute on function public.approve_gp_closeout(uuid,text),public.reject_gp_closeout(uuid,text),public.request_gp_closeout_approval(uuid),public.gp_closeout_queue(),public.approve_zero_invoice_closeout(uuid,text),public.reject_zero_invoice_closeout(uuid,text),public.request_zero_invoice_closeout_approval(uuid),public.zero_invoice_closeout_queue(),public.record_job_callback(uuid,uuid,text,text),public.review_job_callback(uuid,text,numeric,text),public.job_callback_management_queue(),public.technician_callback_snapshot(integer),public.field_closeout_economics() to authenticated;
