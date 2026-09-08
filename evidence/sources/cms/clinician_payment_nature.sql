-- Nature-of-payment breakdown: records vs dollars.
-- Every general-payment record carries one of 16 nature categories.
-- Food and Beverage dominates the record count (individual meal
-- entries per attendee) but a small share of dollars; royalties,
-- consulting, and speaker fees are the opposite. Percentages 0–1.
with totals as (
    select
        count(*) as all_records,
        sum(total_amount_of_payment_usd) as all_dollars
    from main_marts.fct_industry_payments
)
select
    p.nature_of_payment,
    count(*) as records,
    sum(p.total_amount_of_payment_usd) as dollars,
    cast(count(*) as double) / t.all_records as record_share,
    sum(p.total_amount_of_payment_usd) / t.all_dollars as dollar_share
from main_marts.fct_industry_payments as p
cross join totals as t
group by p.nature_of_payment, t.all_records, t.all_dollars
order by dollars desc
