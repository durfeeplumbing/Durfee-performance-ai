create or replace function pg_temp.verify_fsm_recovery() returns jsonb language plpgsql as $$
declare
 owner_auth uuid := gen_random_uuid(); tech_auth uuid := gen_random_uuid();
 owner_id uuid; tech_id uuid; customer_id uuid; job_id uuid; invoice_id uuid;
 invite_token uuid; denied_call text; checks text[] := array[]::text[]; rejected boolean; result jsonb;
begin
 begin
  insert into auth.users(id,email) values(owner_auth,'fsm-qa-owner-'||owner_auth||'@example.invalid'),(tech_auth,'fsm-qa-tech-'||tech_auth||'@example.invalid');
  insert into public.users(email,name,role,active,auth_user_id) values('fsm-qa-owner-'||owner_auth||'@example.invalid','FSM temporary QA owner','owner',true,owner_auth) returning id into owner_id;
  insert into public.users(email,name,role,active,auth_user_id) values('fsm-qa-tech-'||tech_auth||'@example.invalid','FSM temporary QA technician','technician',true,tech_auth) returning id into tech_id;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_auth,'role','authenticated')::text,true);
  set local role authenticated;
  perform public.save_technician_skill_atomic(tech_id,'Plumbing Service',80,false,null,null);
  invite_token := public.create_employee_invite_atomic('fsm-qa-invite-'||owner_auth||'@example.invalid','FSM temporary invite','technician');
  perform public.revoke_employee_invite_atomic(invite_token);
  checks := array_append(checks,'owner provisions technician skills and creates/revokes invite');
  customer_id := public.create_customer_atomic('FSM rollback-only test customer',null,null,'Test address, South Dennis, MA',41.69,-70.16);
  job_id := public.create_job_atomic(customer_id,'Plumbing Service','Rollback-only workflow validation',now()+interval '1 day',now()+interval '1 day 2 hours');
  assert (select status='scheduled' from public.jobs where id=job_id), 'Job did not schedule';
  checks := array_append(checks,'create customer and schedule job');
  perform public.assign_technician_atomic(job_id,tech_id);
  assert (select status='dispatched' and technician_id=tech_id from public.jobs where id=job_id), 'Job did not dispatch';
  checks := array_append(checks,'dispatch to qualified technician');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',tech_auth,'role','authenticated')::text,true);
  rejected:=false;
  begin
   perform public.create_job_invoice_explicit(job_id,10000,false);
  exception when others then
   if sqlerrm not ilike '%permission%' then raise; end if;
   rejected:=true;
  end;
  assert rejected, 'Technician unexpectedly permitted to bill';
  checks := array_append(checks,'technician billing permission denied');
  foreach denied_call in array array[
    format('select private.create_job_invoice_explicit_impl(%L,10000,false)',job_id),
    format('select private.record_invoice_payment_impl(%L,10000,''check'',null)',job_id),
    format('select private.close_job_financially_impl(%L)',job_id),
    'select private.create_employee_invite_atomic(''denied@example.invalid'',''Denied'',''technician'')',
    format('select private.revoke_employee_invite_atomic(%L)',invite_token),
    format('select private.save_technician_skill_atomic_impl(%L,''Plumbing Service'',80,false,null,null)',tech_id)
  ] loop
    rejected:=false;
    begin execute denied_call;
    exception when insufficient_privilege then rejected:=true;
    end;
    assert rejected,'Private implementation permission guard failed: '||denied_call;
  end loop;
  checks := array_append(checks,'direct private billing and team calls denied to technician');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  rejected:=false;
  begin
    perform private.create_customer_atomic_impl('Denied',null,null,'Test address',41.69,-70.16);
  exception when insufficient_privilege then rejected:=true;
  end;
  assert rejected,'Unlinked login unexpectedly permitted to create customer';
  checks := array_append(checks,'unlinked login denied customer creation');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',tech_auth,'role','authenticated')::text,true);
  perform public.set_field_status_atomic(job_id,'en_route',false);
  perform public.set_field_status_atomic(job_id,'on_site',false);
  rejected:=false;
  begin
   perform public.set_field_status_atomic(job_id,'work_complete',true);
  exception when others then
   if sqlerrm not ilike '%Work time is required%' then raise; end if;
   rejected:=true;
  end;
  assert rejected, 'Undocumented work unexpectedly completed';
  checks := array_append(checks,'completion blocked without work documentation');
  perform public.add_work_time_atomic(job_id,1);
  perform public.add_job_note_atomic(job_id,'completion','QA workflow check. No customer work performed.');
  perform public.set_field_status_atomic(job_id,'work_complete',true);
  assert (select status='completed' from public.jobs where id=job_id), 'Work did not complete';
  checks := array_append(checks,'en route, on site, time, notes and work completion');
  perform public.process_completed_job_business_rules(job_id);
  perform public.seed_post_job_followups(job_id);
  checks := array_append(checks,'completion business rules and follow-up queue');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_auth,'role','authenticated')::text,true);
  invoice_id := public.create_job_invoice_explicit(job_id,10000,false);
  assert (select total=10000 and status='open' from public.invoices where id=invoice_id), 'Invoice not created';
  checks := array_append(checks,'owner creates invoice');
  rejected:=false;
  begin
   perform public.record_invoice_payment(invoice_id,10001,'check','QA rollback only');
  exception when others then
   if sqlerrm not ilike '%exceeds remaining balance%' then raise; end if;
   rejected:=true;
  end;
  assert rejected, 'Overpayment unexpectedly accepted';
  checks := array_append(checks,'overpayment blocked');
  perform public.record_invoice_payment(invoice_id,10000,'check','QA rollback only; no actual payment');
  perform public.close_job_financially(job_id);
  assert (select status='closed' from public.jobs where id=job_id), 'Financial closeout failed';
  checks := array_append(checks,'record payment and financial closeout');
  result := jsonb_build_object('status','passed','checks',checks,'test_data','rolled back');
  raise exception using errcode='ZX001',message='Rollback successful QA fixture';
 exception when sqlstate 'ZX001' then
  return result;
 end;
end;
$$;
select pg_temp.verify_fsm_recovery() as verification;
