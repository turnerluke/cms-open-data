-- The headline stat comparing claim-rank vs cost-rank leaderboards on
-- the National file: what share of ALL Part D claims and drug cost do
-- the top 10 by claims (vs the top 10 by cost) account for?
with national as (
    select
        brand_name,
        generic_name,
        total_claims,
        total_drug_cost,
        row_number() over (order by total_claims desc) as claim_rank,
        row_number() over (order by total_drug_cost desc) as cost_rank
    from main_marts.fct_drug_geography
    where geography_level = 'National'
),

totals as (
    select
        sum(total_claims) as all_claims,
        sum(total_drug_cost) as all_cost
    from national
)

select
    -- top 10 by claims: share of claims and share of cost
    sum(case when claim_rank <= 10 then total_claims else 0 end)
    / max(totals.all_claims) as top10_claims_claim_share,
    sum(case when claim_rank <= 10 then total_drug_cost else 0 end)
    / max(totals.all_cost) as top10_claims_cost_share,
    -- top 10 by cost: share of claims and share of cost
    sum(case when cost_rank <= 10 then total_claims else 0 end)
    / max(totals.all_claims) as top10_cost_claim_share,
    sum(case when cost_rank <= 10 then total_drug_cost else 0 end)
    / max(totals.all_cost) as top10_cost_cost_share,
    -- how many drugs appear in both top-10 lists
    sum(case when claim_rank <= 10 and cost_rank <= 10 then 1 else 0 end)
        as overlap_top10
from national, totals
