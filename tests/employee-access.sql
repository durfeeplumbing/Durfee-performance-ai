-- Administrator-only verification. All temporary identities and overrides roll back.
create or replace function pg_temp.verify_employee_access() returns jsonb language plpgsql as $$
declare
  auth_id uuid; employee_id uuid; employee_role text; permission text;
  role_allowed boolean; override_allowed boolean; expected boolean; actual boolean;
  checks integer := 0; result jsonb;
begin
  begin
    foreach employee_role in array array['owner','manager','csr_dispatch','technician','marketing','accounting'] loop
      auth_id := gen_random_uuid();
      insert into auth.users(id,email) values(auth_id,'access-qa-'||auth_id||'@example.invalid');
      insert into public.users(email,name,role,active,auth_user_id)
        values('access-qa-'||auth_id||'@example.invalid','Temporary access verification',employee_role,true,auth_id)
        returning id into employee_id;
      perform set_config('request.jwt.claims',jsonb_build_object('sub',auth_id,'role','authenticated')::text,true);
      set local role authenticated;
      assert exists(select 1 from public.users where auth_user_id=auth_id and active), 'Employee cannot read own linked identity';
      foreach permission in array array['view_dashboard','field_app','view_csr','view_customers','view_accounting'] loop
        select allowed into role_allowed from public.role_permissions where role=employee_role and permission_key=permission;
        select allowed into override_allowed from public.user_permission_overrides where user_id=employee_id and permission_key=permission;
        expected := employee_role='owner' or coalesce(override_allowed,role_allowed,false);
        actual := public.has_permission_for_current_user(permission);
        assert actual=expected, 'Navigation grants differ from database authorization';
        checks := checks+1;
      end loop;
      reset role;
      if employee_role<>'owner' then
        insert into public.user_permission_overrides(user_id,permission_key,allowed) values(employee_id,'view_dashboard',false);
        set local role authenticated;
        assert (select allowed=false from public.user_permission_overrides where user_id=employee_id and permission_key='view_dashboard'), 'Employee cannot read denial override';
        assert not public.has_permission_for_current_user('view_dashboard'), 'Personal denial was ignored';
        checks := checks+1;
        reset role;
      end if;
    end loop;
    update public.users set active=false where id=employee_id;
    set local role authenticated;
    assert not public.has_permission_for_current_user('view_dashboard'), 'Inactive employee retains dashboard access';
    reset role;
    checks := checks+1;
    result := jsonb_build_object('status','passed','checks',checks,'roles',6,'test_data','rolled back');
    raise exception using errcode='ZX001',message='Rollback successful access verification';
  exception when sqlstate 'ZX001' then return result;
  end;
end;
$$;
select pg_temp.verify_employee_access() as verification;
