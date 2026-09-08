-- Compare Part B utilization for clinicians who received any
-- industry payment in 2024 vs those who did not. Restricted to
-- entity_code = 'I' (individual clinicians) — organizational NPIs
-- have their own utilization roll-up and aren't Sunshine recipients.
-- Left join on payments means the "Unpaid" cohort is everyone in
-- fct_physician_utilization with no matching 2024 payment record.
-- This is an observational contrast between two selected
-- populations — Sunshine recipients skew toward specialists who
-- bill drugs/devices, and Part B billing volume is itself a
-- selection factor for both cohorts. Not a causal comparison.
with payments as (
    select
        covered_recipient_npi as npi,
        sum(total_amount_of_payment_usd) as pay_dollars
    from main_marts.fct_industry_payments
    where covered_recipient_npi is not null
    group by 1
),
util_labeled as (
    select
        u.npi,
        u.total_beneficiaries,
        u.total_medicare_payment_amount,
        u.avg_hcc_risk_score,
        u.pct_beneficiaries_dual_eligible,
        case
            when p.pay_dollars > 0 then 'Received payments'
            else 'No payments'
        end as cohort
    from main_marts.fct_physician_utilization as u
    left join payments as p on u.npi = p.npi
    where u.entity_code = 'I'
)
select
    cohort,
    count(*) as clinicians,
    avg(total_beneficiaries) as avg_beneficiaries,
    median(total_beneficiaries) as median_beneficiaries,
    avg(total_medicare_payment_amount) as avg_medicare_payment,
    median(total_medicare_payment_amount) as median_medicare_payment,
    avg(avg_hcc_risk_score) as avg_hcc_risk,
    avg(pct_beneficiaries_dual_eligible) as avg_pct_dual_eligible
from util_labeled
group by 1
order by cohort
