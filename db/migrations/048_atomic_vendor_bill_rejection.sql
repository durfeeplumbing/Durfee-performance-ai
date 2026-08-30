create or replace function public.reject_vendor_bill_atomic(p_bill_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public,private,pg_temp as $$
declare v_user public.users%rowtype;v_bill public.vendor_bill_drafts%rowtype;begin
select * into v_user from public.users where auth_user_id=auth.uid() and active=true limit 1;if v_user.id is null or v_user.role not in ('owner','manager','accounting') then raise exception 'Not authorized';end if;
if nullif(btrim(coalesce(p_reason,'')),'') is null or length(btrim(p_reason))>1000 then raise exception 'Enter a valid rejection reason';end if;
select * into v_bill from public.vendor_bill_drafts where id=p_bill_id for update;if not found then raise exception 'Bill not found';end if;
if v_bill.status<>'needs_review' then raise exception 'Only bills awaiting review can be rejected';end if;
if exists(select 1 from public.accounts_payable_entries where vendor_bill_id=p_bill_id) then raise exception 'Posted bills cannot be rejected';end if;
update public.vendor_bill_drafts set status='rejected',memo=btrim(p_reason),updated_at=now() where id=p_bill_id;
update public.purchase_order_documents set analysis_status='reviewed' where id=v_bill.document_id;
insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_user.id,'reject_vendor_bill','vendor_bill',p_bill_id::text,jsonb_build_object('status',v_bill.status,'memo',v_bill.memo),jsonb_build_object('status','rejected','reason',btrim(p_reason),'document_id',v_bill.document_id));return p_bill_id;end;$$;
revoke all on function public.reject_vendor_bill_atomic(uuid,text) from public;grant execute on function public.reject_vendor_bill_atomic(uuid,text) to authenticated;