-- For each of the top 25 drugs by prescriber-billed cost, the top 10
-- prescribers by cost (10 × 25 = 250 rows).
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
        t.drug_total_cost,
        f.npi,
        trim(
            coalesce(f.prescriber_first_name || ' ', '')
            || f.prescriber_last_org_name
        ) as prescriber_name,
        f.prescriber_type,
        f.city,
        f.state,
        f.total_claims,
        f.total_drug_cost,
        row_number() over (
            partition by f.brand_name, f.generic_name
            order by f.total_drug_cost desc
        ) as prescriber_rank
    from main_marts.fct_prescriber_drug_spending as f
    inner join top_drugs as t using (brand_name, generic_name)
)

select
    brand_name,
    generic_name,
    npi,
    prescriber_name,
    prescriber_type,
    city,
    state,
    total_claims,
    total_drug_cost,
    total_drug_cost / drug_total_cost as share_of_drug_cost,
    prescriber_rank
from ranked
where prescriber_rank <= 10
order by drug_total_cost desc, prescriber_rank
