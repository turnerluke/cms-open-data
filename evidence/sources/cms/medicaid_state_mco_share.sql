-- State-level MCO share of combined Medicaid dollars, one row per
-- disclosed state (50 + DC + PR = 52). State-tier only — the national
-- 'XX' row is excluded. States with fully-suppressed everything roll
-- up to null and are dropped.
select
    state,
    sum(ffs_medicaid_amount_reimbursed) as ffs_medicaid,
    sum(mco_medicaid_amount_reimbursed) as mco_medicaid,
    sum(medicaid_amount_reimbursed) as medicaid_total,
    sum(mco_medicaid_amount_reimbursed) * 1.0
        / nullif(sum(medicaid_amount_reimbursed), 0) as mco_share,
    sum(number_of_prescriptions) as prescriptions
from main_marts.fct_medicaid_drug_state
where is_state_tier and medicaid_amount_reimbursed is not null
group by 1
order by mco_share
