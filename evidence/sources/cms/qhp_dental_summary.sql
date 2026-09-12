-- Individual-market dental plans by actuarial tier. High plans cover
-- more of expected costs (roughly 85% actuarial value in the CMS
-- template) and Low plans cover less (roughly 70%). Summarised across
-- three scenarios: age-40 adult, child age 0–14, child age 18.

with premium_summary as (

    select
        plans.metal_level,
        premiums.scenario,
        count(distinct plans.plan_id) as plans,
        median(premiums.monthly_premium) as median_premium,
        avg(premiums.monthly_premium) as avg_premium,
        min(premiums.monthly_premium) as min_premium,
        max(premiums.monthly_premium) as max_premium
    from main_marts.fct_qhp_premiums as premiums
    inner join
        main_marts.dim_qhp_plan as plans using (plan_id)
    where
        plans.product = 'dental'
        and plans.market = 'individual'
        and premiums.scenario
            in ('individual_age_40', 'child_age_0_14', 'child_age_18')
    group by 1, 2

)

select
    metal_level,
    case scenario
        when 'individual_age_40' then 'Adult age 40'
        when 'child_age_0_14' then 'Child age 0–14'
        when 'child_age_18' then 'Child age 18'
    end as scenario_label,
    plans,
    median_premium,
    avg_premium,
    min_premium,
    max_premium,
    case scenario
        when 'child_age_0_14' then 0
        when 'child_age_18' then 1
        when 'individual_age_40' then 2
    end as scenario_sort
from premium_summary
order by metal_level, scenario_sort
