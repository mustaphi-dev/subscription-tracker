-- Realtime sends only the first character of char(n) values, so streamed rows read
-- 'G' instead of 'GBP'. text has no such problem; the country check already keeps it to 2 letters.
drop trigger profile_base_change on public.profiles;
alter table public.profiles alter column global_base_currency type text, alter column country type text;
create trigger profile_base_change after update of global_base_currency on public.profiles
  for each row execute function public.on_base_change();
alter table public.financial_items alter column original_currency type text;
alter table public.payment_sources alter column currency type text;
alter table public.merchant_prices alter column currency type text;
alter table public.fx_rates alter column base_currency type text, alter column target_currency type text;
