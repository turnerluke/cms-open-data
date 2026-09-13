-- National (state = 'XX') Medicaid drug utilization headline for 2023.
-- Never sum this together with state-tier rows.
select
    sum(total_amount_reimbursed) as total_amount_reimbursed,
    sum(medicaid_amount_reimbursed) as medicaid_amount_reimbursed,
    sum(non_medicaid_amount_reimbursed) as non_medicaid_amount_reimbursed,
    sum(ffs_medicaid_amount_reimbursed) as ffs_medicaid_amount_reimbursed,
    sum(mco_medicaid_amount_reimbursed) as mco_medicaid_amount_reimbursed,
    sum(mco_medicaid_amount_reimbursed) * 1.0
        / nullif(sum(medicaid_amount_reimbursed), 0) as mco_share_of_medicaid,
    sum(mco_total_amount_reimbursed) * 1.0
        / nullif(sum(total_amount_reimbursed), 0) as mco_share_of_total,
    sum(number_of_prescriptions) as number_of_prescriptions,
    count(distinct ndc) as distinct_ndcs,
    count(distinct labeler_code) as distinct_labelers,
    max(as_of) as as_of
from main_marts.fct_medicaid_drug_state
where not is_state_tier
