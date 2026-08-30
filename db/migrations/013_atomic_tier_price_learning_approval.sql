alter table public.price_book_learning_proposals
  add column if not exists price_book_tier_id uuid references public.price_book_tiers(id) on delete set null;

create index if not exists price_book_learning_proposals_tier_idx
  on public.price_book_learning_proposals(price_book_tier_id);

create or replace function public.review_price_book_learning_proposal(p_proposal_id uuid,p_decision text)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_role text;
  v_user_id uuid;
  v_p public.price_book_learning_proposals%rowtype;
  v_min_gp numeric;
  v_allow_below boolean;
  v_before jsonb;
  v_after jsonb;
begin
  v_role:=private.current_employee_role();
  if v_role<>'owner' then raise exception 'Owner approval required'; end if;

  select id into v_user_id
  from public.users
  where auth_user_id=auth.uid() and active=true
  limit 1;
  if v_user_id is null then raise exception 'Active owner user required'; end if;

  if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;

  select * into v_p
  from public.price_book_learning_proposals
  where id=p_proposal_id and status='pending'
  for update;
  if not found then raise exception 'Pending proposal not found'; end if;

  select minimum_gp,allow_owner_below_floor
    into v_min_gp,v_allow_below
  from public.company_pricing_settings
  where id=true;

  if p_decision='approved'
     and v_p.proposed_target_gp<v_min_gp
     and coalesce(v_allow_below,false)=false then
    raise exception 'Proposed GP is below the current company floor';
  end if;

  if p_decision='approved' then
    if v_p.price_book_tier_id is not null then
      select to_jsonb(t) into v_before
      from public.price_book_tiers t
      where t.id=v_p.price_book_tier_id
      for update;
      if v_before is null then raise exception 'Price book tier not found'; end if;

      update public.price_book_tiers
      set labor_hours=v_p.proposed_labor_hours,
          target_gp=v_p.proposed_target_gp,
          updated_at=now()
      where id=v_p.price_book_tier_id;

      select to_jsonb(t) into v_after
      from public.price_book_tiers t
      where t.id=v_p.price_book_tier_id;
    else
      select to_jsonb(i) into v_before
      from public.price_book_items i
      where i.id=v_p.price_book_item_id
      for update;
      if v_before is null then raise exception 'Price book item not found'; end if;

      update public.price_book_items
      set labor_hours=v_p.proposed_labor_hours,
          target_gp=v_p.proposed_target_gp,
          updated_at=now()
      where id=v_p.price_book_item_id;

      select to_jsonb(i) into v_after
      from public.price_book_items i
      where i.id=v_p.price_book_item_id;
    end if;
  end if;

  update public.price_book_learning_proposals
  set status=p_decision,reviewed_at=now(),reviewed_by=v_user_id
  where id=p_proposal_id;

  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data)
  values(
    v_user_id,
    p_decision||'_price_learning_proposal',
    'price_book_learning_proposal',
    p_proposal_id,
    jsonb_build_object('proposal_status','pending','pricebook',v_before),
    jsonb_build_object(
      'proposal_status',p_decision,
      'pricebook',v_after,
      'price_book_item_id',v_p.price_book_item_id,
      'price_book_tier_id',v_p.price_book_tier_id,
      'proposed_labor_hours',v_p.proposed_labor_hours,
      'proposed_target_gp',v_p.proposed_target_gp
    )
  );
end;
$$;

revoke all on function public.review_price_book_learning_proposal(uuid,text) from public,anon;
grant execute on function public.review_price_book_learning_proposal(uuid,text) to authenticated;
