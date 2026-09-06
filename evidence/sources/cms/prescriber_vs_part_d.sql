-- Top 25 drugs by prescriber-billed cost, joined to the same drug's
-- gross Part D spending (manufacturer roll-up, latest year) via
-- drug_key. The key is derived identically in both facts and staging
-- strips the Part D spending file's trailing-`*` aggregate marker,
-- so a NULL part_d_total_spending means the drug is genuinely absent
-- from the Part D spending file (none of the current top 25 are).
with top_drugs as (
    select
        brand_name,
        generic_name,
        -- drug_key is a pure function of upper(brand) + upper(generic),
        -- so it is constant within the group
        max(drug_key) as drug_key,
        sum(total_drug_cost) as prescriber_billed_cost
    from main_marts.fct_prescriber_drug_spending
    group by 1, 2
    order by prescriber_billed_cost desc
    limit 25
),

part_d_latest as (
    select
        drug_key,
        spending_year,
        total_spending
    from main_marts.fct_part_d_drug_spending
    where
        is_manufacturer_rollup
        and spending_year = (
            select max(spending_year)
            from main_marts.fct_part_d_drug_spending
        )
)

select
    t.brand_name,
    t.generic_name,
    t.prescriber_billed_cost,
    p.total_spending as part_d_total_spending,
    p.spending_year as part_d_spending_year,
    t.prescriber_billed_cost / p.total_spending as billed_to_gross_ratio
from top_drugs as t
left join part_d_latest as p using (drug_key)
order by t.prescriber_billed_cost desc
