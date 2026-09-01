create or replace function private.global_system_search_impl(p_query text, p_limit_per_category integer default 8)
returns table(category text,title text,subtitle text,href text,sort_rank integer)
language plpgsql
security definer
set search_path=''
as $$
declare q text:=trim(coalesce(p_query,'')); lim integer:=greatest(1,least(coalesce(p_limit_per_category,8),20));
begin
  if length(q)<2 then return; end if;

  if private.has_permission('view_customers') then
    return query select 'Customers'::text,c.name::text,concat_ws(' • ',nullif(c.phone,''),nullif(c.email,''),nullif(c.service_address,''))::text,('/customers/'||c.id)::text,10
    from public.customers c where concat_ws(' ',c.name,c.phone,c.email,c.service_address,c.customer_code) ilike '%'||q||'%' order by case when c.name ilike q||'%' then 0 else 1 end,c.name limit lim;
  end if;

  if private.has_permission('view_jobs') then
    return query select 'Jobs'::text,concat(coalesce(j.service_type,'Job'),' • ',left(j.id::text,8))::text,concat_ws(' • ',c.name,j.status,j.service_summary)::text,('/jobs/'||j.id)::text,20
    from public.jobs j left join public.customers c on c.id=j.customer_id where concat_ws(' ',j.id::text,j.service_type,j.service_summary,j.status,c.name,c.phone,c.service_address) ilike '%'||q||'%' order by j.created_at desc limit lim;
  end if;

  if private.has_permission('view_estimates') then
    return query select 'Estimates'::text,concat('Estimate • ',left(e.id::text,8))::text,concat_ws(' • ',c.name,e.status,e.approved_option)::text,('/jobs/'||e.job_id)::text,30
    from public.estimates e join public.jobs j on j.id=e.job_id left join public.customers c on c.id=j.customer_id where concat_ws(' ',e.id::text,e.status,e.approved_option,c.name,j.service_type,j.service_summary) ilike '%'||q||'%' order by e.created_at desc limit lim;
  end if;

  if private.has_permission('view_billing') then
    return query select 'Invoices'::text,concat('Invoice • ',left(i.id::text,8))::text,concat_ws(' • ',c.name,i.status,('$'||round(coalesce(i.total,0),2)::text))::text,('/jobs/'||i.job_id)::text,40
    from public.invoices i join public.jobs j on j.id=i.job_id left join public.customers c on c.id=j.customer_id where concat_ws(' ',i.id::text,i.status,c.name,j.service_type,j.service_summary,i.total::text) ilike '%'||q||'%' order by i.created_at desc limit lim;
  end if;

  if private.has_permission('view_inventory') then
    return query select 'Inventory'::text,concat_ws(' • ',nullif(ii.sku,''),ii.description)::text,concat_ws(' • ',nullif(ii.barcode,''),nullif(ii.bin_code,''),nullif(il.name,''),case when ii.on_hand is not null then 'On hand '||ii.on_hand::text end)::text,'/inventory'::text,50
    from public.inventory_items ii left join public.inventory_locations il on il.id=ii.location_id where concat_ws(' ',ii.sku,ii.description,ii.barcode,ii.bin_code,ii.supplier_sku,ii.location,il.name) ilike '%'||q||'%' order by ii.description limit lim;
  end if;

  if private.has_permission('view_pricebook') then
    return query select 'Price Book'::text,concat_ws(' • ',nullif(p.code,''),p.name)::text,concat_ws(' • ',p.category,p.description)::text,'/pricebook'::text,60
    from public.price_book_items p where concat_ws(' ',p.code,p.name,p.category,p.description) ilike '%'||q||'%' order by p.name limit lim;
  end if;

  if private.has_permission('view_purchasing') then
    return query select 'Purchase Orders'::text,coalesce(nullif(po.po_number,''),concat('PO • ',left(po.id::text,8)))::text,concat_ws(' • ',s.name,c.name,po.status,po.notes)::text,'/purchasing'::text,70
    from public.purchase_orders po left join public.suppliers s on s.id=po.supplier_id left join public.customers c on c.id=po.customer_id where concat_ws(' ',po.id::text,po.po_number,po.status,po.notes,s.name,s.vendor_code,s.account_number,c.name) ilike '%'||q||'%' order by po.created_at desc limit lim;

    return query select 'Suppliers'::text,s.name::text,concat_ws(' • ',s.vendor_code,s.phone,s.email,s.account_number)::text,'/purchasing'::text,80
    from public.suppliers s where concat_ws(' ',s.name,s.vendor_code,s.phone,s.email,s.account_number,s.website) ilike '%'||q||'%' order by s.name limit lim;
  end if;

  if private.has_permission('view_team') then
    return query select 'Team'::text,u.name::text,concat_ws(' • ',u.role,u.email,case when u.active then 'Active' else 'Inactive' end)::text,'/team'::text,90
    from public.users u where concat_ws(' ',u.name,u.email,u.role) ilike '%'||q||'%' order by u.name limit lim;
  end if;

  if private.has_permission('view_csr') then
    return query select 'Communications'::text,concat(upper(cc.channel),' • ',coalesce(c.name,'Unknown customer'))::text,concat_ws(' • ',cc.direction,cc.status,cc.subject,left(coalesce(cc.body,cc.ai_summary,cc.transcript,''),160))::text,'/communications'::text,100
    from public.customer_communications cc left join public.customers c on c.id=cc.customer_id where concat_ws(' ',c.name,c.phone,c.email,cc.from_address,cc.to_address,cc.subject,cc.body,cc.ai_summary,cc.transcript,cc.disposition) ilike '%'||q||'%' order by cc.occurred_at desc limit lim;

    return query select 'Reviews'::text,concat('Review • ',coalesce(c.name,'Customer'))::text,concat_ws(' • ',r.status,r.channel,r.rating::text,r.feedback,r.review_platform)::text,'/reviews'::text,110
    from public.customer_review_requests r left join public.customers c on c.id=r.customer_id where concat_ws(' ',c.name,r.status,r.channel,r.rating::text,r.feedback,r.review_platform,r.manager_note) ilike '%'||q||'%' order by r.created_at desc limit lim;
  end if;

  if private.has_permission('view_jobs') then
    return query select 'Callbacks'::text,concat('Callback • ',left(cb.original_job_id::text,8))::text,concat_ws(' • ',c.name,cb.reason,cb.preventability,cb.manager_note)::text,('/jobs/'||cb.original_job_id)::text,120
    from public.job_callbacks cb join public.jobs j on j.id=cb.original_job_id left join public.customers c on c.id=j.customer_id where concat_ws(' ',c.name,cb.reason,cb.preventability,cb.manager_note,cb.original_job_id::text,cb.callback_job_id::text) ilike '%'||q||'%' order by cb.created_at desc limit lim;
  end if;
end;
$$;

create or replace function public.global_system_search(p_query text,p_limit_per_category integer default 8)
returns table(category text,title text,subtitle text,href text,sort_rank integer)
language plpgsql
security invoker
set search_path=''
as $$begin return query select * from private.global_system_search_impl(p_query,p_limit_per_category); end$$;

revoke all on function public.global_system_search(text,integer) from public,anon;
grant execute on function public.global_system_search(text,integer) to authenticated;
grant execute on function private.global_system_search_impl(text,integer) to authenticated;
