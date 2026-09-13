-- Top drugs by CLAIM volume from `fct_drug_geography` National rows.
-- Kept as its own extract (rather than reusing `prescriber_top_drugs`,
-- which ranks by cost from the detail file) so the page can put a
-- claim-count leaderboard next to a cost leaderboard and highlight
-- their zero overlap. `is_opioid` / `is_antibiotic` flags are pulled
-- through for the caveats.
select
    brand_name,
    generic_name,
    total_prescribers,
    total_claims,
    total_drug_cost,
    total_drug_cost / nullif(total_claims, 0) as cost_per_claim,
    is_opioid,
    is_antibiotic
from main_marts.fct_drug_geography
where geography_level = 'National'
order by total_claims desc
limit 10
