-- Step 1: schema, RLS, FX conversion, shortfall view, roll-forward, cron.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- ───────────── profiles ─────────────
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  global_base_currency char(3) not null default 'GBP',
  fcm_token text,
  inbound_parse_email text unique,
  biometric_enabled boolean not null default true
);

-- Auto-create profile + unique inbound address on sign-up.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, inbound_parse_email)
  values (new.id, 'trials+' || replace(new.id::text, '-', '') || '@inbound.subtracker.app');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────── payment_sources ─────────────
create table public.payment_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade default auth.uid(),
  provider text not null check (provider in ('revolut','wise','lloyds','paypal')),
  account_name text not null,
  current_balance numeric(14,2) not null default 0,
  currency char(3) not null default 'GBP',
  gbp_equivalent_balance numeric(14,2),
  external_account_id text,
  last_synced_at timestamptz,
  unique (user_id, external_account_id)
);
create index on public.payment_sources (user_id);

-- ───────────── financial_items ─────────────
create table public.financial_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade default auth.uid(),
  payment_source_id uuid references public.payment_sources on delete set null,
  item_type text not null check (item_type in ('subscription','free_trial','installment','income')),
  merchant_name text not null,
  original_amount numeric(14,2) not null default 0,
  original_currency char(3) not null default 'GBP',
  -- Base-currency value of the NEXT charge (post_trial_amount for trials). Kept by trigger.
  gbp_equivalent_amount numeric(14,2),
  post_trial_amount numeric(14,2),
  next_renewal_date date,
  trial_end_date timestamptz,
  billing_cycle text not null default 'monthly' check (billing_cycle in ('weekly','monthly','quarterly','yearly','once')),
  installment_total_count int,
  installment_paid_count int default 0,
  installment_remaining_balance numeric(14,2),
  cancellation_url text,
  status text not null default 'active' check (status in ('active','cancelled','completed','pending_confirmation')),
  auto_detected_via text not null default 'manual' check (auto_detected_via in ('open_banking','email_ai','manual')),
  total_spent numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);
create index on public.financial_items (user_id, next_renewal_date);
create index on public.financial_items (payment_source_id);
create index on public.financial_items (trial_end_date) where item_type = 'free_trial' and status = 'active';

-- ───────────── fx_rates ─────────────
-- Rows are stored against a single pivot (USD); to_base() cross-converts.
create table public.fx_rates (
  base_currency char(3) not null,
  target_currency char(3) not null,
  rate numeric(20,10) not null,
  updated_at timestamptz not null default now(),
  primary key (base_currency, target_currency)
);

-- ───────────── alert_logs ─────────────
create table public.alert_logs (
  id uuid primary key default gen_random_uuid(),
  financial_item_id uuid references public.financial_items on delete cascade,
  payment_source_id uuid references public.payment_sources on delete cascade,
  alert_stage text not null check (alert_stage in ('7_days','3_days','24_hours','shortfall','confirm_trial')),
  sent_at timestamptz not null default now()
);
create unique index alert_once_per_item_stage on public.alert_logs (financial_item_id, alert_stage)
  where financial_item_id is not null;
create index on public.alert_logs (payment_source_id, sent_at);

-- ───────────── server-only tables (no policies => service role only) ─────────────
create table public.bank_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  provider text not null,
  requisition_id text unique,          -- GoCardless requisition
  reference text unique not null,      -- OAuth state nonce
  status text not null default 'pending',
  created_at timestamptz not null default now()
);
create table public.merchant_prices (
  merchant_key text primary key,       -- lower-case normalised merchant name
  amount numeric(14,2) not null,
  currency char(3) not null,
  billing_cycle text not null default 'monthly',
  cancellation_url text
);
insert into public.merchant_prices values
  ('netflix', 10.99, 'GBP', 'monthly', 'https://www.netflix.com/cancelplan'),
  ('spotify', 11.99, 'GBP', 'monthly', 'https://www.spotify.com/account/subscription/'),
  ('disney', 9.99, 'GBP', 'monthly', 'https://www.disneyplus.com/account/subscription'),
  ('amazon prime', 8.99, 'GBP', 'monthly', 'https://www.amazon.co.uk/mc/pipelines/cancellation'),
  ('apple', 6.99, 'GBP', 'monthly', 'https://apps.apple.com/account/subscriptions'),
  ('youtube', 12.99, 'GBP', 'monthly', 'https://www.youtube.com/paid_memberships'),
  ('chatgpt', 20.00, 'USD', 'monthly', 'https://chatgpt.com/#settings/Subscription'),
  ('claude', 18.00, 'GBP', 'monthly', 'https://claude.ai/settings/billing');

-- ───────────── RLS ─────────────
alter table public.profiles enable row level security;
alter table public.payment_sources enable row level security;
alter table public.financial_items enable row level security;
alter table public.fx_rates enable row level security;
alter table public.alert_logs enable row level security;
alter table public.bank_connections enable row level security;
alter table public.merchant_prices enable row level security;

create policy "own profile" on public.profiles for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "own sources" on public.payment_sources for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own items" on public.financial_items for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "fx readable" on public.fx_rates for select to authenticated using (true);
create policy "own alerts" on public.alert_logs for select to authenticated using (
  exists (select 1 from public.financial_items f where f.id = financial_item_id and f.user_id = (select auth.uid()))
  or exists (select 1 from public.payment_sources s where s.id = payment_source_id and s.user_id = (select auth.uid())));

-- Users may not change their own inbound address (column revoke is a no-op under a table grant).
revoke update on public.profiles from authenticated, anon;
grant update (global_base_currency, fcm_token, biometric_enabled) on public.profiles to authenticated;

-- ───────────── FX conversion ─────────────
create function public.to_base(amount numeric, from_ccy text, to_ccy text) returns numeric
language sql stable set search_path = '' as $$
  select case
    when amount is null then null
    when upper(from_ccy) = upper(to_ccy) then amount
    else round(amount * t.rate / f.rate, 2)
  end
  from (select 1) _
  left join public.fx_rates f on f.base_currency = 'USD' and f.target_currency = upper(from_ccy)
  left join public.fx_rates t on t.base_currency = 'USD' and t.target_currency = upper(to_ccy)
$$;

create function public.user_base(uid uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select global_base_currency from public.profiles where id = uid), 'GBP')
$$;

create function public.fill_base_amounts() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name = 'financial_items' then
    new.gbp_equivalent_amount := public.to_base(
      case when new.item_type = 'free_trial' then coalesce(new.post_trial_amount, 0) else new.original_amount end,
      new.original_currency, public.user_base(new.user_id));
  else
    new.gbp_equivalent_balance := public.to_base(new.current_balance, new.currency, public.user_base(new.user_id));
  end if;
  return new;
end $$;
create trigger items_base before insert or update on public.financial_items
  for each row execute function public.fill_base_amounts();
create trigger sources_base before insert or update on public.payment_sources
  for each row execute function public.fill_base_amounts();

-- Re-run conversion for everyone (after FX sync) or one user (after base switch).
create function public.refresh_base_amounts(uid uuid default null) returns void
language sql security definer set search_path = '' as $$
  update public.financial_items set id = id where uid is null or user_id = uid;
  update public.payment_sources set id = id where uid is null or user_id = uid;
$$;
revoke execute on function public.refresh_base_amounts from public, anon, authenticated;

create function public.on_base_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.refresh_base_amounts(new.id);
  return new;
end $$;
create trigger profile_base_change after update of global_base_currency on public.profiles
  for each row execute function public.on_base_change();

-- ───────────── Shortfall check (next 7 days, per account) ─────────────
-- Trials reserve their post-trial amount on trial_end_date even while £0.00 today.
create view public.shortfall_check with (security_invoker = true) as
with due as (
  select f.payment_source_id,
         sum(f.gbp_equivalent_amount) as due_amount,
         count(*) as item_count,
         min(coalesce(f.trial_end_date::date, f.next_renewal_date)) as first_due
  from public.financial_items f
  where f.status = 'active' and f.item_type <> 'income'
    and coalesce(case when f.item_type = 'free_trial' then f.trial_end_date::date end, f.next_renewal_date)
        between current_date and current_date + 7
  group by f.payment_source_id
)
select s.id as payment_source_id, s.user_id, s.provider, s.account_name,
       s.gbp_equivalent_balance as balance,
       d.due_amount, d.item_count, d.first_due,
       (d.first_due - current_date) as days_until_first,
       greatest(d.due_amount - coalesce(s.gbp_equivalent_balance, 0), 0) as shortfall
from public.payment_sources s
join due d on d.payment_source_id = s.id
where d.due_amount > coalesce(s.gbp_equivalent_balance, 0);

-- ───────────── Daily roll-forward ─────────────
create function public.roll_forward_items() returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- Trials that passed their end date without cancellation become paid subscriptions.
  update public.financial_items
     set item_type = 'subscription',
         original_amount = coalesce(post_trial_amount, original_amount),
         next_renewal_date = trial_end_date::date
   where item_type = 'free_trial' and status = 'active' and trial_end_date < now();

  -- Charges that hit: book spend, advance date, tick installments.
  update public.financial_items
     set total_spent = total_spent + original_amount,
         installment_paid_count = case when item_type = 'installment' then installment_paid_count + 1 else installment_paid_count end,
         installment_remaining_balance = case when item_type = 'installment'
           then greatest(installment_remaining_balance - original_amount, 0) else installment_remaining_balance end,
         status = case
           when billing_cycle = 'once' then 'completed'
           when item_type = 'installment' and installment_paid_count + 1 >= installment_total_count then 'completed'
           else status end,
         next_renewal_date = next_renewal_date + case billing_cycle
           when 'weekly' then interval '7 days' when 'monthly' then interval '1 month'
           when 'quarterly' then interval '3 months' when 'yearly' then interval '1 year'
           else interval '0' end
   where status = 'active' and item_type <> 'free_trial' and next_renewal_date < current_date;
end $$;

-- ───────────── Cron (edge function URL + service key live in Vault) ─────────────
-- select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'functions_url');
-- select vault.create_secret('<service_role_key>', 'service_key');
create function public.call_function(fn text) returns void
language sql security definer set search_path = '' as $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'functions_url') || '/' || fn,
    headers := jsonb_build_object('Authorization', 'Bearer ' ||
      (select decrypted_secret from vault.decrypted_secrets where name = 'service_key')),
    body := '{}'::jsonb);
$$;
revoke execute on function public.call_function from public, anon, authenticated;

select cron.schedule('fx-sync',        '0 */6 * * *',  $$select public.call_function('fx-sync')$$);
select cron.schedule('bank-sync',      '15 */6 * * *', $$select public.call_function('bank-sync/sync-all')$$);
select cron.schedule('roll-forward',   '5 0 * * *',    $$select public.roll_forward_items()$$);
select cron.schedule('dispatch-alerts','*/30 * * * *', $$select public.call_function('dispatch-alerts')$$);

-- Live streams in the app (RLS still applies).
alter publication supabase_realtime add table public.financial_items, public.payment_sources, public.profiles;
