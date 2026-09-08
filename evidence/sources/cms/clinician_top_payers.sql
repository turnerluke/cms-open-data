-- Top 15 paying manufacturers / GPOs by dollars.
-- Rolled up on `paying_manufacturer_or_gpo_id` (never raw name);
-- `any_value(name)` returns one deterministic display label per id
-- so the same entity filed under mixed-case variants collapses to a
-- single row.
select
    paying_manufacturer_or_gpo_id as payer_id,
    any_value(paying_manufacturer_or_gpo_name) as payer_name,
    count(*) as records,
    count(distinct covered_recipient_npi) as clinicians_paid,
    sum(total_amount_of_payment_usd) as dollars
from main_marts.fct_industry_payments
group by 1
order by dollars desc
limit 15
