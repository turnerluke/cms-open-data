-- Top 15 covered-recipient specialties by total industry-payment
-- dollars. `covered_recipient_specialty` is the NUCC taxonomy path
-- reported on each payment record (pipe-delimited); one row per
-- taxonomy string. Teaching-hospital rows carry no specialty and
-- are excluded.
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
order by dollars desc
limit 15
