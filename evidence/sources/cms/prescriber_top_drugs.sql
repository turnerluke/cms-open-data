-- Top 25 drugs (brand + generic grain) by prescriber-billed cost.
select
    brand_name,
    generic_name,
    count(*) as prescribers,
    sum(total_claims) as total_claims,
    sum(total_drug_cost) as total_drug_cost,
    sum(total_drug_cost) / nullif(sum(total_claims), 0) as cost_per_claim
from main_marts.fct_prescriber_drug_spending
group by 1, 2
order by total_drug_cost desc
limit 25
