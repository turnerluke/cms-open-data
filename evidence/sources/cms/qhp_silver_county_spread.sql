-- Lowest-cost silver premium per county (age-40 individual medical),
-- one row per county. Used for the county-level spread chart.

select
    counties.state_code,
    counties.fips_county_code,
    counties.county_name,
    min(premiums.monthly_premium) as min_silver_premium
from main_marts.fct_qhp_premiums as premiums
inner join
    main_marts.dim_qhp_plan as plans using (plan_id)
inner join
    main_marts.dim_county as counties using (fips_county_code)
where
    plans.product = 'medical'
    and plans.market = 'individual'
    and plans.metal_level = 'Silver'
    and premiums.scenario = 'individual_age_40'
group by 1, 2, 3
order by min_silver_premium
