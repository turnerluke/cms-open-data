-- Top drugs by DRUG COST from `fct_drug_geography` National rows.
-- Paired with `drug_geography_claim_leaders` to show that the top of
-- each ranking has essentially no overlap: cheap high-volume generics
-- top the claim list, expensive low-volume brands top the cost list.
select
    brand_name,
    generic_name,
    total_prescribers,
    total_claims,
    total_drug_cost,
    total_drug_cost / nullif(total_claims, 0) as cost_per_claim
from main_marts.fct_drug_geography
where geography_level = 'National'
order by total_drug_cost desc
limit 10
