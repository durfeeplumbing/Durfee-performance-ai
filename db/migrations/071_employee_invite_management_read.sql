create policy employee_invites_management_read on public.employee_invites for select to authenticated using (private.has_permission('manage_team'));
