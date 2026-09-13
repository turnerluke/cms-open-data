-- Top 15 NDCs nationally (XX-tier) by Medicaid reimbursement, with a
-- representative CMS `product_name` pulled from the raw SDUD file
-- because the mart is intentionally NDC-keyed (product_name is
-- truncated at 10 chars in the source and a single NDC can carry
-- multiple truncated strings — see the mart docs). Aggregation is
-- always by NDC; the name is display-only. `any_value` picks one of
-- the (usually identical) truncated strings for each NDC.
with names as (
    select
        "NDC" as ndc,
        any_value("Product Name") as product_name
    from read_parquet(
        '../data/raw/cms_medicaid_state_drug_utilization_2023/*.parquet'
    )
    where "Product Name" is not null
    group by 1
)

select
    m.ndc,
    n.product_name,
    m.labeler_code,
    m.number_of_prescriptions,
    m.total_amount_reimbursed,
    m.medicaid_amount_reimbursed,
    m.ffs_medicaid_amount_reimbursed,
    m.mco_medicaid_amount_reimbursed,
    m.mco_share_of_medicaid_amount,
    m.medicaid_amount_reimbursed
        / nullif(m.number_of_prescriptions, 0) as medicaid_per_rx
from main_marts.fct_medicaid_drug_state as m
left join names as n using (ndc)
where not m.is_state_tier and m.medicaid_amount_reimbursed is not null
order by m.medicaid_amount_reimbursed desc
limit 15
