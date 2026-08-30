alter table public.estimates
  add column if not exists approved_option_id uuid references public.estimate_options(id) on delete set null;

create index if not exists estimates_approved_option_id_idx
  on public.estimates(approved_option_id);
