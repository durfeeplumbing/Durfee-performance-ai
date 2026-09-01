alter table public.inventory_items
  add column if not exists barcode text,
  add column if not exists bin_code text,
  add column if not exists max_stock numeric,
  add column if not exists last_counted_at timestamptz,
  add column if not exists last_counted_by uuid references public.users(id) on delete set null;

alter table public.inventory_items
  add constraint inventory_items_max_stock_nonnegative check (max_stock is null or max_stock >= 0);

create unique index if not exists inventory_items_barcode_unique_idx on public.inventory_items(barcode) where barcode is not null and btrim(barcode) <> '';
create index if not exists inventory_items_last_counted_by_idx on public.inventory_items(last_counted_by);

create table public.inventory_location_stock (
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  location_id uuid not null references public.inventory_locations(id) on delete cascade,
  on_hand numeric not null default 0 check (on_hand >= 0),
  reorder_point numeric not null default 0 check (reorder_point >= 0),
  max_stock numeric check (max_stock is null or max_stock >= 0),
  bin_code text,
  updated_at timestamptz not null default now(),
  primary key (inventory_item_id, location_id)
);
create index inventory_location_stock_location_id_idx on public.inventory_location_stock(location_id);
alter table public.inventory_location_stock enable row level security;
revoke all on table public.inventory_location_stock from public, anon, authenticated;

create table public.inventory_cycle_counts (
  id uuid primary key default gen_random_uuid(),
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  location_id uuid not null references public.inventory_locations(id) on delete restrict,
  expected_quantity numeric not null check (expected_quantity >= 0),
  counted_quantity numeric not null check (counted_quantity >= 0),
  variance numeric not null,
  photo_url text,
  note text,
  counted_by uuid not null references public.users(id) on delete restrict,
  counted_at timestamptz not null default now()
);
create index inventory_cycle_counts_item_counted_idx on public.inventory_cycle_counts(inventory_item_id, counted_at desc);
create index inventory_cycle_counts_location_counted_idx on public.inventory_cycle_counts(location_id, counted_at desc);
create index inventory_cycle_counts_counted_by_idx on public.inventory_cycle_counts(counted_by);
alter table public.inventory_cycle_counts enable row level security;
revoke all on table public.inventory_cycle_counts from public, anon, authenticated;

create table public.supplier_cost_observations (
  id uuid primary key default gen_random_uuid(),
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  supplier_sku text,
  unit_cost numeric not null check (unit_cost >= 0),
  source text not null check (source in ('manual','purchase_order','vendor_invoice','supplyhouse','supplier_feed')),
  observed_at timestamptz not null default now(),
  recorded_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index supplier_cost_observations_item_observed_idx on public.supplier_cost_observations(inventory_item_id, observed_at desc);
create index supplier_cost_observations_supplier_idx on public.supplier_cost_observations(supplier_id, observed_at desc);
create index supplier_cost_observations_recorded_by_idx on public.supplier_cost_observations(recorded_by);
alter table public.supplier_cost_observations enable row level security;
revoke all on table public.supplier_cost_observations from public, anon, authenticated;

create or replace function private.create_inventory_location_impl(p_name text,p_location_type text,p_assigned_user_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id uuid; v_name text; v_type text;
begin
  if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  v_name:=btrim(coalesce(p_name,'')); v_type:=lower(btrim(coalesce(p_location_type,'')));
  if v_name='' or v_type not in ('warehouse','truck','shop','other') then raise exception 'Invalid inventory location'; end if;
  if p_assigned_user_id is not null and not exists(select 1 from public.users where id=p_assigned_user_id and active=true) then raise exception 'Assigned user unavailable'; end if;
  insert into public.inventory_locations(name,location_type,assigned_user_id) values(v_name,v_type,p_assigned_user_id) returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'create_inventory_location','inventory_location',v_id::text,jsonb_build_object('name',v_name,'location_type',v_type,'assigned_user_id',p_assigned_user_id));
  return v_id;
end$$;

create or replace function private.update_inventory_item_operations_impl(p_inventory_item_id uuid,p_location_id uuid,p_barcode text,p_bin_code text,p_max_stock numeric,p_supplier_id uuid,p_supplier_sku text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_item public.inventory_items%rowtype; v_location public.inventory_locations%rowtype; v_barcode text; v_bin text; v_supplier_sku text;
begin
  if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_inventory_item_id is null or (p_max_stock is not null and p_max_stock<0) then raise exception 'Invalid inventory configuration'; end if;
  select * into v_item from public.inventory_items where id=p_inventory_item_id for update;
  if not found then raise exception 'Inventory item not found'; end if;
  if p_location_id is not null then select * into v_location from public.inventory_locations where id=p_location_id and active=true; if not found then raise exception 'Inventory location not found'; end if; end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and active=true) then raise exception 'Supplier not found'; end if;
  v_barcode:=nullif(btrim(coalesce(p_barcode,'')),''); v_bin:=nullif(btrim(coalesce(p_bin_code,'')),''); v_supplier_sku:=nullif(btrim(coalesce(p_supplier_sku,'')),'');
  update public.inventory_items set location_id=p_location_id,location=coalesce(v_location.name,location),barcode=v_barcode,bin_code=v_bin,max_stock=p_max_stock,supplier_id=p_supplier_id,supplier_sku=v_supplier_sku where id=p_inventory_item_id;
  if p_location_id is not null then insert into public.inventory_location_stock(inventory_item_id,location_id,on_hand,reorder_point,max_stock,bin_code) values(p_inventory_item_id,p_location_id,v_item.on_hand,v_item.reorder_point,p_max_stock,v_bin) on conflict(inventory_item_id,location_id) do update set reorder_point=excluded.reorder_point,max_stock=excluded.max_stock,bin_code=excluded.bin_code,updated_at=now(); end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_actor,'configure_inventory_item','inventory_item',p_inventory_item_id::text,jsonb_build_object('location_id',v_item.location_id,'barcode',v_item.barcode,'bin_code',v_item.bin_code,'max_stock',v_item.max_stock,'supplier_id',v_item.supplier_id,'supplier_sku',v_item.supplier_sku),jsonb_build_object('location_id',p_location_id,'barcode',v_barcode,'bin_code',v_bin,'max_stock',p_max_stock,'supplier_id',p_supplier_id,'supplier_sku',v_supplier_sku));
  return p_inventory_item_id;
end$$;

create or replace function private.record_inventory_cycle_count_impl(p_inventory_item_id uuid,p_location_id uuid,p_counted_quantity numeric,p_photo_url text default null,p_note text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_item public.inventory_items%rowtype; v_expected numeric; v_variance numeric; v_count_id uuid; v_total numeric;
begin
  if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_inventory_item_id is null or p_location_id is null or p_counted_quantity is null or p_counted_quantity<0 then raise exception 'Invalid cycle count'; end if;
  select * into v_item from public.inventory_items where id=p_inventory_item_id for update; if not found then raise exception 'Inventory item not found'; end if;
  if not exists(select 1 from public.inventory_locations where id=p_location_id and active=true) then raise exception 'Inventory location not found'; end if;
  insert into public.inventory_location_stock(inventory_item_id,location_id,on_hand,reorder_point,max_stock,bin_code) values(p_inventory_item_id,p_location_id,case when v_item.location_id=p_location_id then v_item.on_hand else 0 end,v_item.reorder_point,v_item.max_stock,v_item.bin_code) on conflict(inventory_item_id,location_id) do nothing;
  select on_hand into v_expected from public.inventory_location_stock where inventory_item_id=p_inventory_item_id and location_id=p_location_id for update;
  v_variance:=p_counted_quantity-v_expected;
  update public.inventory_location_stock set on_hand=p_counted_quantity,updated_at=now() where inventory_item_id=p_inventory_item_id and location_id=p_location_id;
  select coalesce(sum(on_hand),0) into v_total from public.inventory_location_stock where inventory_item_id=p_inventory_item_id;
  update public.inventory_items set on_hand=v_total,last_counted_at=now(),last_counted_by=v_actor where id=p_inventory_item_id;
  insert into public.inventory_cycle_counts(inventory_item_id,location_id,expected_quantity,counted_quantity,variance,photo_url,note,counted_by) values(p_inventory_item_id,p_location_id,v_expected,p_counted_quantity,v_variance,nullif(btrim(coalesce(p_photo_url,'')),''),nullif(btrim(coalesce(p_note,'')),''),v_actor) returning id into v_count_id;
  if v_variance<>0 then insert into public.inventory_transactions(inventory_item_id,location_id,transaction_type,quantity,unit_cost,actor_user_id) values(p_inventory_item_id,p_location_id,'adjustment',v_variance,v_item.unit_cost,v_actor); end if;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,before_data,after_data) values(v_actor,'inventory_cycle_count','inventory_item',p_inventory_item_id::text,jsonb_build_object('location_id',p_location_id,'expected_quantity',v_expected),jsonb_build_object('count_id',v_count_id,'counted_quantity',p_counted_quantity,'variance',v_variance,'aggregate_on_hand',v_total));
  return v_count_id;
end$$;

create or replace function private.transfer_inventory_stock_impl(p_inventory_item_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_quantity numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_item public.inventory_items%rowtype; v_from numeric; v_tx uuid;
begin
  if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1;
  if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  if p_inventory_item_id is null or p_from_location_id is null or p_to_location_id is null or p_from_location_id=p_to_location_id or coalesce(p_quantity,0)<=0 then raise exception 'Invalid stock transfer'; end if;
  select * into v_item from public.inventory_items where id=p_inventory_item_id for update; if not found then raise exception 'Inventory item not found'; end if;
  if (select count(*) from public.inventory_locations where id in (p_from_location_id,p_to_location_id) and active=true)<>2 then raise exception 'Inventory location not found'; end if;
  insert into public.inventory_location_stock(inventory_item_id,location_id,on_hand,reorder_point,max_stock,bin_code) values(p_inventory_item_id,p_from_location_id,case when v_item.location_id=p_from_location_id then v_item.on_hand else 0 end,v_item.reorder_point,v_item.max_stock,v_item.bin_code) on conflict(inventory_item_id,location_id) do nothing;
  insert into public.inventory_location_stock(inventory_item_id,location_id,on_hand,reorder_point,max_stock,bin_code) values(p_inventory_item_id,p_to_location_id,0,v_item.reorder_point,v_item.max_stock,null) on conflict(inventory_item_id,location_id) do nothing;
  select on_hand into v_from from public.inventory_location_stock where inventory_item_id=p_inventory_item_id and location_id=p_from_location_id for update; perform 1 from public.inventory_location_stock where inventory_item_id=p_inventory_item_id and location_id=p_to_location_id for update;
  if v_from<p_quantity then raise exception 'Insufficient stock at source location'; end if;
  update public.inventory_location_stock set on_hand=on_hand-p_quantity,updated_at=now() where inventory_item_id=p_inventory_item_id and location_id=p_from_location_id;
  update public.inventory_location_stock set on_hand=on_hand+p_quantity,updated_at=now() where inventory_item_id=p_inventory_item_id and location_id=p_to_location_id;
  insert into public.inventory_transactions(inventory_item_id,location_id,transaction_type,quantity,unit_cost,actor_user_id) values(p_inventory_item_id,p_from_location_id,'adjustment',-p_quantity,v_item.unit_cost,v_actor) returning id into v_tx;
  insert into public.inventory_transactions(inventory_item_id,location_id,transaction_type,quantity,unit_cost,actor_user_id) values(p_inventory_item_id,p_to_location_id,'adjustment',p_quantity,v_item.unit_cost,v_actor);
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'inventory_stock_transfer','inventory_item',p_inventory_item_id::text,jsonb_build_object('from_location_id',p_from_location_id,'to_location_id',p_to_location_id,'quantity',p_quantity));
  return v_tx;
end$$;

create or replace function private.record_supplier_cost_observation_impl(p_inventory_item_id uuid,p_supplier_id uuid,p_supplier_sku text,p_unit_cost numeric,p_source text,p_observed_at timestamptz default now())
returns uuid language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id uuid; v_source text;
begin
  if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if;
  select id into v_actor from public.users where auth_user_id=auth.uid() and active=true limit 1; if v_actor is null then raise exception 'Employee identity unavailable'; end if;
  v_source:=lower(btrim(coalesce(p_source,'')));
  if p_inventory_item_id is null or not exists(select 1 from public.inventory_items where id=p_inventory_item_id) or coalesce(p_unit_cost,-1)<0 or v_source not in ('manual','purchase_order','vendor_invoice','supplyhouse','supplier_feed') then raise exception 'Invalid supplier cost observation'; end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and active=true) then raise exception 'Supplier not found'; end if;
  insert into public.supplier_cost_observations(inventory_item_id,supplier_id,supplier_sku,unit_cost,source,observed_at,recorded_by) values(p_inventory_item_id,p_supplier_id,nullif(btrim(coalesce(p_supplier_sku,'')),''),p_unit_cost,v_source,coalesce(p_observed_at,now()),v_actor) returning id into v_id;
  insert into public.audit_log(actor_user_id,action,entity_type,entity_id,after_data) values(v_actor,'record_supplier_cost_observation','inventory_item',p_inventory_item_id::text,jsonb_build_object('observation_id',v_id,'supplier_id',p_supplier_id,'supplier_sku',nullif(btrim(coalesce(p_supplier_sku,'')),''),'unit_cost',p_unit_cost,'source',v_source)); return v_id;
end$$;

create or replace function private.inventory_operations_snapshot_impl(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not (private.has_permission('view_inventory') or private.has_permission('manage_inventory')) then raise exception 'Permission denied'; end if;
  return jsonb_build_object(
    'locations',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]'::jsonb) from (select id,name,location_type,assigned_user_id,active from public.inventory_locations where active=true) x),
    'stock',(select coalesce(jsonb_agg(to_jsonb(x) order by x.description,x.location_name),'[]'::jsonb) from (select s.inventory_item_id,s.location_id,i.sku,i.description,l.name location_name,l.location_type,s.on_hand,s.reorder_point,s.max_stock,s.bin_code,s.updated_at from public.inventory_location_stock s join public.inventory_items i on i.id=s.inventory_item_id join public.inventory_locations l on l.id=s.location_id order by s.updated_at desc limit greatest(1,least(coalesce(p_limit,100),500))) x),
    'counts',(select coalesce(jsonb_agg(to_jsonb(x) order by x.counted_at desc),'[]'::jsonb) from (select c.id,c.inventory_item_id,i.sku,i.description,c.location_id,l.name location_name,c.expected_quantity,c.counted_quantity,c.variance,c.photo_url,c.note,c.counted_at,u.name counted_by_name from public.inventory_cycle_counts c join public.inventory_items i on i.id=c.inventory_item_id join public.inventory_locations l on l.id=c.location_id left join public.users u on u.id=c.counted_by order by c.counted_at desc limit greatest(1,least(coalesce(p_limit,100),500))) x),
    'costs',(select coalesce(jsonb_agg(to_jsonb(x) order by x.observed_at desc),'[]'::jsonb) from (select o.id,o.inventory_item_id,i.sku,i.description,o.supplier_id,s.name supplier_name,o.supplier_sku,o.unit_cost,o.source,o.observed_at from public.supplier_cost_observations o join public.inventory_items i on i.id=o.inventory_item_id left join public.suppliers s on s.id=o.supplier_id order by o.observed_at desc limit greatest(1,least(coalesce(p_limit,100),500))) x)
  );
end$$;

create or replace function public.create_inventory_location(p_name text,p_location_type text,p_assigned_user_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$ begin if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if; return private.create_inventory_location_impl(p_name,p_location_type,p_assigned_user_id); end $$;
create or replace function public.update_inventory_item_operations(p_inventory_item_id uuid,p_location_id uuid,p_barcode text,p_bin_code text,p_max_stock numeric,p_supplier_id uuid,p_supplier_sku text) returns uuid language plpgsql security invoker set search_path='' as $$ begin if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if; return private.update_inventory_item_operations_impl(p_inventory_item_id,p_location_id,p_barcode,p_bin_code,p_max_stock,p_supplier_id,p_supplier_sku); end $$;
create or replace function public.record_inventory_cycle_count(p_inventory_item_id uuid,p_location_id uuid,p_counted_quantity numeric,p_photo_url text default null,p_note text default null) returns uuid language plpgsql security invoker set search_path='' as $$ begin if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if; return private.record_inventory_cycle_count_impl(p_inventory_item_id,p_location_id,p_counted_quantity,p_photo_url,p_note); end $$;
create or replace function public.transfer_inventory_stock(p_inventory_item_id uuid,p_from_location_id uuid,p_to_location_id uuid,p_quantity numeric) returns uuid language plpgsql security invoker set search_path='' as $$ begin if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if; return private.transfer_inventory_stock_impl(p_inventory_item_id,p_from_location_id,p_to_location_id,p_quantity); end $$;
create or replace function public.record_supplier_cost_observation(p_inventory_item_id uuid,p_supplier_id uuid,p_supplier_sku text,p_unit_cost numeric,p_source text,p_observed_at timestamptz default now()) returns uuid language plpgsql security invoker set search_path='' as $$ begin if not private.has_permission('manage_inventory') then raise exception 'Permission denied'; end if; return private.record_supplier_cost_observation_impl(p_inventory_item_id,p_supplier_id,p_supplier_sku,p_unit_cost,p_source,p_observed_at); end $$;
create or replace function public.inventory_operations_snapshot(p_limit integer default 100) returns jsonb language plpgsql security invoker set search_path='' as $$ begin if not (private.has_permission('view_inventory') or private.has_permission('manage_inventory')) then raise exception 'Permission denied'; end if; return private.inventory_operations_snapshot_impl(p_limit); end $$;

revoke all on function private.create_inventory_location_impl(text,text,uuid) from public,anon;
revoke all on function private.update_inventory_item_operations_impl(uuid,uuid,text,text,numeric,uuid,text) from public,anon;
revoke all on function private.record_inventory_cycle_count_impl(uuid,uuid,numeric,text,text) from public,anon;
revoke all on function private.transfer_inventory_stock_impl(uuid,uuid,uuid,numeric) from public,anon;
revoke all on function private.record_supplier_cost_observation_impl(uuid,uuid,text,numeric,text,timestamptz) from public,anon;
revoke all on function private.inventory_operations_snapshot_impl(integer) from public,anon;
grant execute on function private.create_inventory_location_impl(text,text,uuid) to authenticated;
grant execute on function private.update_inventory_item_operations_impl(uuid,uuid,text,text,numeric,uuid,text) to authenticated;
grant execute on function private.record_inventory_cycle_count_impl(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function private.transfer_inventory_stock_impl(uuid,uuid,uuid,numeric) to authenticated;
grant execute on function private.record_supplier_cost_observation_impl(uuid,uuid,text,numeric,text,timestamptz) to authenticated;
grant execute on function private.inventory_operations_snapshot_impl(integer) to authenticated;
revoke all on function public.create_inventory_location(text,text,uuid) from public,anon;
revoke all on function public.update_inventory_item_operations(uuid,uuid,text,text,numeric,uuid,text) from public,anon;
revoke all on function public.record_inventory_cycle_count(uuid,uuid,numeric,text,text) from public,anon;
revoke all on function public.transfer_inventory_stock(uuid,uuid,uuid,numeric) from public,anon;
revoke all on function public.record_supplier_cost_observation(uuid,uuid,text,numeric,text,timestamptz) from public,anon;
revoke all on function public.inventory_operations_snapshot(integer) from public,anon;
grant execute on function public.create_inventory_location(text,text,uuid) to authenticated;
grant execute on function public.update_inventory_item_operations(uuid,uuid,text,text,numeric,uuid,text) to authenticated;
grant execute on function public.record_inventory_cycle_count(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.transfer_inventory_stock(uuid,uuid,uuid,numeric) to authenticated;
grant execute on function public.record_supplier_cost_observation(uuid,uuid,text,numeric,text,timestamptz) to authenticated;
grant execute on function public.inventory_operations_snapshot(integer) to authenticated;