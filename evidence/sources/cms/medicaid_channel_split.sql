-- FFS vs MCO split at the national (XX-tier) level, drawn from
-- fct_medicaid_medicare_drug_spend so `Medicaid Total` doesn't
-- double-count the two channels. One row per program label.
select
    program_name,
    total_spending,
    total_claims,
    total_spending / nullif(total_claims, 0) as spending_per_claim
from main_marts.fct_medicaid_medicare_drug_spend
where program_name in ('Medicaid FFS', 'Medicaid MCO', 'Medicaid Total')
order by
    case program_name
        when 'Medicaid FFS' then 1
        when 'Medicaid MCO' then 2
        when 'Medicaid Total' then 3
    end
