-- For the top-25 drugs by national cost, how much does state-level
-- cost-per-beneficiary vary? Restricted to the 50 states + DC (2-digit
-- FIPS-style codes, excluding the 9x pseudo-codes and territory codes)
-- so ratios aren't dominated by tiny special populations. Only rows
-- with non-NULL `cost_per_beneficiary` are counted.
with top_drugs as (

    select brand_name, generic_name, total_drug_cost as national_cost
    from main_marts.fct_drug_geography
    where geography_level = 'National'
    order by total_drug_cost desc
    limit 25

),

state_rows as (

    select
        g.brand_name,
        g.generic_name,
        g.geography_description,
        g.cost_per_beneficiary,
        g.national_total_drug_cost
        / nullif(g.national_total_beneficiaries, 0) as national_cost_per_beneficiary,
        t.national_cost
    from main_marts.fct_drug_geography as g
    inner join top_drugs as t
        on
            g.brand_name = t.brand_name
            and g.generic_name = t.generic_name
    where
        g.geography_level = 'State'
        and g.cost_per_beneficiary is not null
        -- 50 states + DC only
        and length(g.geography_code) = 2
        and g.geography_code not like '9%'
        and g.geography_code not in ('60', '66', '69', '72', '78')

)

select
    brand_name,
    generic_name,
    max(national_cost) as national_cost,
    max(national_cost_per_beneficiary) as national_cost_per_beneficiary,
    min(cost_per_beneficiary) as min_state_cost_per_beneficiary,
    max(cost_per_beneficiary) as max_state_cost_per_beneficiary,
    max(cost_per_beneficiary)
    / nullif(min(cost_per_beneficiary), 0) as max_min_ratio,
    count(*) as states_reporting
from state_rows
group by brand_name, generic_name
order by max(cost_per_beneficiary) / nullif(min(cost_per_beneficiary), 0) desc
