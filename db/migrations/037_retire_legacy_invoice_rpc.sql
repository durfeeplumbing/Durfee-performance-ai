-- Retire the legacy two-argument invoice creation RPC.
-- All invoice creation must use create_job_invoice_explicit(...), which requires
-- an explicit owner acknowledgement before deviating from approved estimate pricing.

revoke all on function public.create_job_invoice(uuid,numeric) from public;
revoke all on function public.create_job_invoice(uuid,numeric) from authenticated;
drop function if exists public.create_job_invoice(uuid,numeric);
