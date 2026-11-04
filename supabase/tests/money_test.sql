-- FX conversion, 7-day shortfall (incl. trial reservation), roll-forward and RLS isolation.
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/money_test.sql   (rolls back; leaves no data)
begin;

insert into auth.users values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');
insert into public.profiles (id) values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b')
  on conflict do nothing;
insert into public.fx_rates (base_currency, target_currency, rate) values
  ('USD','USD',1), ('USD','GBP',0.79), ('USD','GHS',15.9), ('USD','EUR',0.92)
  on conflict (base_currency, target_currency) do update set rate = excluded.rate;

insert into public.payment_sources (id, user_id, provider, account_name, current_balance, currency) values
  ('00000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-00000000000a', 'revolut', 'Main', 18.20, 'GBP');

insert into public.financial_items (user_id, payment_source_id, item_type, merchant_name, original_amount, original_currency,
                                    post_trial_amount, next_renewal_date, trial_end_date, status, billing_cycle,
                                    installment_total_count, installment_paid_count, installment_remaining_balance) values
  -- in window
  ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000051','subscription','Sub USD',15,'USD',null,current_date+2,null,'active','monthly',null,0,null),
  ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000051','free_trial','Trial GHS',0,'GHS',250,null,now()+interval '4 days','active','monthly',null,0,null),
  -- out of window / excluded
  ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000051','subscription','Later',99,'GBP',null,current_date+10,null,'active','monthly',null,0,null),
  ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000051','subscription','Cancelled',99,'GBP',null,current_date+1,null,'cancelled','monthly',null,0,null),
  -- roll-forward fixtures
  ('00000000-0000-0000-0000-00000000000a',null,'subscription','Past sub',10,'GBP',null,current_date-1,null,'active','monthly',null,0,null),
  ('00000000-0000-0000-0000-00000000000a',null,'free_trial','Past trial',0,'GBP',7.99,null,now()-interval '1 hour','active','monthly',null,0,null),
  ('00000000-0000-0000-0000-00000000000a',null,'installment','Pay in 3',35,'GBP',null,current_date-1,null,'active','monthly',3,2,35);

do $$
declare r record;
begin
  assert (select gbp_equivalent_amount from public.financial_items where merchant_name = 'Sub USD') = 11.85, 'USD→GBP';
  assert (select gbp_equivalent_amount from public.financial_items where merchant_name = 'Trial GHS') = 12.42, 'trial reserves post-trial GHS→GBP';

  select * into r from public.shortfall_check;
  assert r.due_amount = 24.27, format('due %s', r.due_amount);
  assert r.shortfall = 6.07, format('shortfall %s', r.shortfall);
  assert r.days_until_first = 2, format('days %s', r.days_until_first);

  perform public.roll_forward_items();
  select * into r from public.financial_items where merchant_name = 'Past sub';
  assert r.next_renewal_date = (current_date - 1 + interval '1 month')::date and r.total_spent = 10, 'subscription advanced';
  select * into r from public.financial_items where merchant_name = 'Past trial';
  assert r.item_type = 'subscription' and r.original_amount = 7.99, 'trial converted to paid';
  select * into r from public.financial_items where merchant_name = 'Pay in 3';
  assert r.status = 'completed' and r.installment_paid_count = 3 and r.installment_remaining_balance = 0, 'installment completed';

  -- Base switch re-converts.
  update public.profiles set global_base_currency = 'USD' where id = '00000000-0000-0000-0000-00000000000a';
  assert (select gbp_equivalent_amount from public.financial_items where merchant_name = 'Sub USD') = 15, 'base switch';
end $$;

-- RLS: user B sees none of user A's rows.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', true);
do $$ begin
  assert (select count(*) from public.financial_items) = 0, 'RLS items';
  assert (select count(*) from public.shortfall_check) = 0, 'RLS shortfall view';
end $$;

rollback;
\echo money_test passed

-- Inbound address is server-assigned only.
begin;
insert into auth.users values ('00000000-0000-0000-0000-00000000000c');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', true);
update public.profiles set global_base_currency = 'EUR';  -- allowed
do $$ begin
  update public.profiles set inbound_parse_email = 'x@evil.test';
  raise exception 'inbound_parse_email should not be updatable';
exception when insufficient_privilege then null;
end $$;
rollback;
\echo inbound_email_test passed
