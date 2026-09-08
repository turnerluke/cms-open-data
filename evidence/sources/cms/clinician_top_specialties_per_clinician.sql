-- Top 15 specialties by dollars per paid clinician, restricted to
-- specialties with at least 100 paid clinicians so a handful of
-- royalty recipients don't dominate.
select
    covered_recipient_specialty as specialty,
    count(distinct covered_recipient_npi) as clinicians,
    sum(total_amount_of_payment_usd) as dollars,
    sum(total_amount_of_payment_usd)
        / nullif(count(distinct covered_recipient_npi), 0)
        as dollars_per_clinician
from main_marts.fct_industry_payments
where
    covered_recipient_specialty is not null
    and covered_recipient_npi is not null
group by 1
having count(distinct covered_recipient_npi) >= 100
order by dollars_per_clinician desc
limit 15
