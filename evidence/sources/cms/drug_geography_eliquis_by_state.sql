-- Cost per beneficiary for Eliquis (the largest Part D drug by cost)
-- across the 50 states + DC, with the national benchmark carried on
-- every row so the page can plot a reference line. Eliquis is used as
-- the hero drug because it has the highest national spend and
-- non-NULL cost_per_beneficiary in every state.
select
    geography_code,
    geography_description as state,
    total_prescribers,
    total_beneficiaries,
    cost_per_beneficiary,
    national_total_drug_cost
    / nullif(national_total_beneficiaries, 0) as national_cost_per_beneficiary,
    share_of_national_cost
from main_marts.fct_drug_geography
where
    geography_level = 'State'
    and brand_name = 'Eliquis'
    and cost_per_beneficiary is not null
    and length(geography_code) = 2
    and geography_code not like '9%'
    and geography_code not in ('60', '66', '69', '72', '78')
order by cost_per_beneficiary desc
