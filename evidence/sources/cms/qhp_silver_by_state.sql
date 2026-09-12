-- Lowest-cost silver individual-medical monthly premium per county
-- for a 40-year-old, aggregated to state. FFM-only (30 states on
-- HealthCare.gov); state-based-exchange states are absent.

with per_county as (

    select
        counties.state_code,
        premiums.fips_county_code,
        min(premiums.monthly_premium) as min_silver_premium,
        median(premiums.monthly_premium) as median_silver_premium,
        count(distinct plans.plan_id) as silver_plans
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
    group by 1, 2

)

select
    state_code,
    count(*) as counties,
    avg(min_silver_premium) as avg_lowest_silver_premium,
    median(min_silver_premium) as median_lowest_silver_premium,
    min(min_silver_premium) as min_silver_premium,
    max(min_silver_premium) as max_silver_premium,
    avg(silver_plans) as avg_silver_plans_per_county
from per_county
group by 1
order by avg_lowest_silver_premium
