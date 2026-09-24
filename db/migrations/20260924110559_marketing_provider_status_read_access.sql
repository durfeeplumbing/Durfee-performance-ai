-- The summary RPCs are security invoker functions. Give callers only their
-- required read columns, with the same employee permissions enforced by RLS.
grant select (
  provider, connection_status, external_account_id, account_name,
  authorized_at, last_synced_at, last_error
) on public.marketing_provider_connections to authenticated;
grant select (provider, status, conversion_event_id)
  on public.marketing_conversion_sync_queue to authenticated;
grant select (id, value, event_time)
  on public.marketing_conversion_events to authenticated;

create policy marketing_provider_status_read
  on public.marketing_provider_connections
  for select to authenticated
  using (
    (select auth.uid()) is not null
    and (
      (select public.has_permission_for_current_user('view_reports'))
      or (select public.has_permission_for_current_user('view_csr'))
    )
  );

create policy marketing_sync_queue_report_read
  on public.marketing_conversion_sync_queue
  for select to authenticated
  using (
    (select auth.uid()) is not null
    and (select public.has_permission_for_current_user('view_reports'))
  );

create policy marketing_conversion_value_report_read
  on public.marketing_conversion_events
  for select to authenticated
  using (
    (select auth.uid()) is not null
    and (select public.has_permission_for_current_user('view_reports'))
  );

-- No writes, token-vault access, or anonymous access are granted.
notify pgrst, 'reload schema';
