insert into public.permission_definitions(permission_key,label,category,sort_order) values ('view_purchasing','View purchasing','Inventory',92),('manage_purchasing','Manage purchasing','Inventory',93) on conflict(permission_key) do nothing;
insert into public.role_permissions(role,permission_key,allowed) values
('owner','view_purchasing',true),('owner','manage_purchasing',true),
('manager','view_purchasing',true),('manager','manage_purchasing',true),
('accounting','view_purchasing',true),('accounting','manage_purchasing',true),
('csr_dispatch','view_purchasing',false),('csr_dispatch','manage_purchasing',false),
('technician','view_purchasing',false),('technician','manage_purchasing',false),
('marketing','view_purchasing',false),('marketing','manage_purchasing',false)
on conflict(role,permission_key) do nothing;