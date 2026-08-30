alter table public.estimate_options
  add column if not exists price_book_tier_id uuid references public.price_book_tiers(id) on delete set null;

create index if not exists estimate_options_price_book_tier_idx
  on public.estimate_options(price_book_tier_id);
