create index if not exists marketing_conversion_events_customer_idx on public.marketing_conversion_events(customer_id,event_time desc);
create index if not exists marketing_conversion_events_invoice_idx on public.marketing_conversion_events(invoice_id) where invoice_id is not null;
create index if not exists marketing_conversion_events_payment_idx on public.marketing_conversion_events(payment_id) where payment_id is not null;
