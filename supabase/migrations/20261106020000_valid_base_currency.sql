-- Display currency must be a three-letter ISO 4217 code. Repair any other value
-- (falling back to GBP) so formatting never shows a bare letter, then enforce it.
update public.profiles set global_base_currency = 'GBP'
  where global_base_currency !~ '^[A-Z]{3}$';
alter table public.profiles add constraint profiles_base_currency_iso
  check (global_base_currency ~ '^[A-Z]{3}$');
