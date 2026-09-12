-- Distribution of age-40 individual monthly premiums by metal tier.
-- One row per metal level, medical individual market only.

select
    plans.metal_level,
    count(distinct plans.plan_id) as plans,
    count(*) as plan_county_offerings,
    min(premiums.monthly_premium) as min_premium,
    quantile_cont(premiums.monthly_premium, 0.10) as p10_premium,
    quantile_cont(premiums.monthly_premium, 0.25) as p25_premium,
    median(premiums.monthly_premium) as median_premium,
    quantile_cont(premiums.monthly_premium, 0.75) as p75_premium,
    quantile_cont(premiums.monthly_premium, 0.90) as p90_premium,
    max(premiums.monthly_premium) as max_premium,
    avg(premiums.monthly_premium) as avg_premium,
    case plans.metal_level
        when 'Catastrophic' then 0
        when 'Bronze' then 1
        when 'Expanded Bronze' then 2
        when 'Silver' then 3
        when 'Gold' then 4
        when 'Platinum' then 5
        else 99
    end as metal_sort
from main_marts.fct_qhp_premiums as premiums
inner join main_marts.dim_qhp_plan as plans using (plan_id)
where
    plans.product = 'medical'
    and plans.market = 'individual'
    and premiums.scenario = 'individual_age_40'
group by 1
order by metal_sort
