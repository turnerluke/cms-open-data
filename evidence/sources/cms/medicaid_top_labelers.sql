-- Top 15 NDC labeler codes (roughly, manufacturers) nationally by
-- Medicaid reimbursement — a supplementary view of "where the money
-- goes" that isn't affected by the 10-char product-name truncation.
-- XX-tier only.
select
    labeler_code,
    count(distinct ndc) as ndcs,
    sum(number_of_prescriptions) as prescriptions,
    sum(medicaid_amount_reimbursed) as medicaid_spend,
    sum(total_amount_reimbursed) as total_spend
from main_marts.fct_medicaid_drug_state
where not is_state_tier and medicaid_amount_reimbursed is not null
group by 1
order by medicaid_spend desc
limit 15
