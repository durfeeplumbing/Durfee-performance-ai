-- Reduce accidental unauthenticated Data API exposure without changing existing signed-in app behavior.
revoke execute on function public.refresh_service_titan_customer_mapping_candidates() from public, anon;
revoke execute on function public.service_titan_sync_status_summary() from public, anon;

-- Future public-schema objects must be explicitly opened to anonymous clients.
alter default privileges for role postgres in schema public revoke select, insert, update, delete on tables from anon;
alter default privileges for role postgres in schema public revoke usage, select on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;
