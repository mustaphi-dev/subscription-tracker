-- Any bank, entered by hand (balance kept up to date by the user, not Open Banking).
alter table public.payment_sources drop constraint payment_sources_provider_check;
alter table public.payment_sources add constraint payment_sources_provider_check
  check (provider in ('revolut','wise','lloyds','paypal','other'));
alter table public.payment_sources add column institution text;  -- display name, e.g. "Monzo", "GCB Bank"
alter table public.payment_sources add column is_manual boolean not null default false;
