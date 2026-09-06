select
    state,
    count(distinct npi) as prescribers,
    sum(total_claims) as total_claims,
    sum(total_drug_cost) as total_drug_cost,
    sum(total_drug_cost) / count(distinct npi) as cost_per_prescriber
from main_marts.fct_prescriber_drug_spending
group by 1
order by total_drug_cost desc
