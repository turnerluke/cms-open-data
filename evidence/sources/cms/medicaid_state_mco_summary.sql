-- Summary counters over the per-state MCO shares — how many states
-- run essentially FFS-only (a "pharmacy carve-out"), how many run
-- essentially MCO-only, and the median. State-tier only.
with per_state as (
    select
        state,
        sum(mco_medicaid_amount_reimbursed) * 1.0
            / nullif(sum(medicaid_amount_reimbursed), 0) as mco_share
    from main_marts.fct_medicaid_drug_state
    where is_state_tier and medicaid_amount_reimbursed is not null
    group by 1
)

select
    count(*) as states,
    sum(case when mco_share < 0.10 then 1 else 0 end) as carve_out_states,
    sum(case when mco_share > 0.90 then 1 else 0 end) as mco_dominant_states,
    avg(mco_share) as mean_mco_share,
    median(mco_share) as median_mco_share,
    min(mco_share) as min_mco_share,
    max(mco_share) as max_mco_share
from per_state
