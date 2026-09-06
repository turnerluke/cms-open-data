-- For each of the top 25 drugs by prescriber-billed cost: what share of
-- the drug's cost comes from its top 1% of prescribers (by cost)? The
-- top-1% headcount is ceil(1% of the drug's prescribers), so every drug
-- gets at least one top prescriber.
with top_drugs as (
    select
        brand_name,
        generic_name,
        sum(total_drug_cost) as drug_total_cost
    from main_marts.fct_prescriber_drug_spending
    group by 1, 2
    order by drug_total_cost desc
    limit 25
),

ranked as (
    select
        f.brand_name,
        f.generic_name,
        f.total_drug_cost,
        row_number() over (
            partition by f.brand_name, f.generic_name
            order by f.total_drug_cost desc
        ) as cost_rank,
        count(*) over (
            partition by f.brand_name, f.generic_name
        ) as prescriber_count
    from main_marts.fct_prescriber_drug_spending as f
    inner join top_drugs as t using (brand_name, generic_name)
)

select
    brand_name,
    generic_name,
    max(prescriber_count) as prescribers,
    cast(ceil(max(prescriber_count) * 0.01) as integer) as top_1pct_prescribers,
    sum(total_drug_cost) as total_drug_cost,
    sum(
        case
            when cost_rank <= ceil(prescriber_count * 0.01) then total_drug_cost
        end
    ) / sum(total_drug_cost) as top_1pct_cost_share
from ranked
group by 1, 2
order by total_drug_cost desc
