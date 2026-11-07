-- No 'gocardless' aggregator exists; every insert names its aggregator.
alter table public.bank_connections alter column aggregator drop default;

-- first_due used the trial end date even for non-trials, while the window filter used it only for trials.
-- institution is appended so alerts can name the bank like the app does.
create or replace view public.shortfall_check with (security_invoker = true) as
with due as (
  select f.payment_source_id,
         sum(public.to_base(
           case when f.item_type = 'free_trial' then coalesce(f.post_trial_amount, 0) else f.original_amount end,
           f.original_currency, s.currency)) as due_amount,
         count(*) as item_count,
         min(coalesce(case when f.item_type = 'free_trial' then f.trial_end_date::date end, f.next_renewal_date)) as first_due
  from public.financial_items f
  join public.payment_sources s on s.id = f.payment_source_id
  where f.status = 'active' and f.item_type <> 'income'
    and coalesce(case when f.item_type = 'free_trial' then f.trial_end_date::date end, f.next_renewal_date)
        between current_date and current_date + 7
  group by f.payment_source_id
)
select s.id as payment_source_id, s.user_id, s.provider, s.account_name,
       s.current_balance as balance,
       d.due_amount, d.item_count, d.first_due,
       (d.first_due - current_date) as days_until_first,
       greatest(d.due_amount - coalesce(s.current_balance, 0), 0) as shortfall,
       s.currency, s.institution
from public.payment_sources s
join due d on d.payment_source_id = s.id
where d.due_amount > coalesce(s.current_balance, 0);
