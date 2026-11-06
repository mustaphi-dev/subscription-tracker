-- Where the user banks (ISO 3166-1 alpha-2). Null until they pick it after sign-up.
-- Decides the default base currency and whether automatic bank linking is offered.
alter table public.profiles add column country char(2) check (country ~ '^[A-Z]{2}$');
grant update (country) on public.profiles to authenticated;

-- Which bank-data aggregator a connection belongs to, so more than one can run side by side
-- (e.g. one for the UK, another for Nigeria). Existing rows are GoCardless.
alter table public.bank_connections add column aggregator text not null default 'gocardless';
alter table public.bank_connections rename column requisition_id to external_id;

-- Any bank the aggregator returns, not only the original four.
alter table public.payment_sources drop constraint payment_sources_provider_check;
