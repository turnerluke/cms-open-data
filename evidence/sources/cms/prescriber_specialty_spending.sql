select
    -- 17 rows (2 NPIs) carry no specialty; label them explicitly
    coalesce(prescriber_type, 'Unknown') as prescriber_type,
    count(distinct npi) as prescribers,
    sum(total_claims) as total_claims,
    sum(total_drug_cost) as total_drug_cost,
    sum(total_drug_cost) / nullif(sum(total_claims), 0) as cost_per_claim
from main_marts.fct_prescriber_drug_spending
group by 1
order by total_drug_cost desc
