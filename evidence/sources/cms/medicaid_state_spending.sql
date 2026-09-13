-- Top 15 states by Medicaid drug spending (state-tier only, combined
-- FFS + MCO channel). Raw dollars — per-capita is not available
-- because SDUD carries no enrollment column.
select
    state,
    sum(ffs_medicaid_amount_reimbursed) as ffs_medicaid,
    sum(mco_medicaid_amount_reimbursed) as mco_medicaid,
    sum(medicaid_amount_reimbursed) as medicaid_total,
    sum(number_of_prescriptions) as prescriptions,
    sum(medicaid_amount_reimbursed)
        / nullif(sum(number_of_prescriptions), 0) as medicaid_per_rx
from main_marts.fct_medicaid_drug_state
where is_state_tier and medicaid_amount_reimbursed is not null
group by 1
order by medicaid_total desc
limit 15
