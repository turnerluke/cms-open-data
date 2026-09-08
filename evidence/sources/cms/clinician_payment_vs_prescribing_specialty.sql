-- Specialty-level roll-up joining industry payments to prescribing.
-- One row per `prescriber_type` (from fct_prescriber_drug_spending's
-- self-reported specialty; 182 distinct values), limited to
-- specialties with ≥ 500 prescribers so small residual buckets
-- don't dominate. `paid_share` is the fraction of a specialty's
-- prescribers who also received any industry payment in 2024.
with payments as (
    select
        covered_recipient_npi as npi,
        sum(total_amount_of_payment_usd) as pay_dollars
    from main_marts.fct_industry_payments
    where covered_recipient_npi is not null
    group by 1
),
scripts as (
    select
        npi,
        prescriber_type,
        sum(total_drug_cost) as rx_dollars,
        sum(total_claims) as rx_claims
    from main_marts.fct_prescriber_drug_spending
    group by 1, 2
),
joined as (
    select
        s.npi,
        s.prescriber_type,
        coalesce(p.pay_dollars, 0) as pay_dollars,
        s.rx_dollars,
        s.rx_claims
    from scripts as s
    left join payments as p on s.npi = p.npi
    where s.prescriber_type is not null
)
select
    prescriber_type,
    count(*) as prescribers,
    count(case when pay_dollars > 0 then 1 end) as paid_prescribers,
    cast(count(case when pay_dollars > 0 then 1 end) as double)
        / count(*) as paid_share,
    sum(pay_dollars) as total_pay_dollars,
    sum(rx_dollars) as total_rx_dollars,
    sum(rx_dollars) / nullif(sum(rx_claims), 0) as rx_cost_per_claim
from joined
group by 1
having count(*) >= 500
order by total_rx_dollars desc
limit 20
