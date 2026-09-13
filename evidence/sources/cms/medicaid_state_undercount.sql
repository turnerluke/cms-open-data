-- Compare CMS's unsuppressed national aggregate (state = 'XX') against
-- the sum of the 52 disclosed state rows so the small-cell suppression
-- gap can be quoted honestly on the state-ranking sections.
with national as (
    select
        sum(total_amount_reimbursed) as total_amount_reimbursed,
        sum(medicaid_amount_reimbursed) as medicaid_amount_reimbursed
    from main_marts.fct_medicaid_drug_state
    where not is_state_tier
),

state_tier as (
    select
        sum(total_amount_reimbursed) as total_amount_reimbursed,
        sum(medicaid_amount_reimbursed) as medicaid_amount_reimbursed,
        count(distinct state) as states,
        sum(case when total_amount_reimbursed is null then 1 else 0 end)
            as fully_suppressed_rows,
        count(*) as state_rows
    from main_marts.fct_medicaid_drug_state
    where is_state_tier
)

select
    national.total_amount_reimbursed as national_total,
    national.medicaid_amount_reimbursed as national_medicaid,
    state_tier.total_amount_reimbursed as state_tier_total,
    state_tier.medicaid_amount_reimbursed as state_tier_medicaid,
    national.total_amount_reimbursed - state_tier.total_amount_reimbursed
        as suppression_gap_total,
    national.medicaid_amount_reimbursed - state_tier.medicaid_amount_reimbursed
        as suppression_gap_medicaid,
    1 - state_tier.total_amount_reimbursed
        / nullif(national.total_amount_reimbursed, 0) as suppression_gap_share,
    state_tier.states,
    state_tier.state_rows,
    state_tier.fully_suppressed_rows,
    cast(state_tier.fully_suppressed_rows as double) / state_tier.state_rows
        as fully_suppressed_share
from national, state_tier
