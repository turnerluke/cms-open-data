-- Issuer concentration in each FFM state, computed as a
-- Herfindahl-Hirschman Index over each issuer's share of individual
-- medical plan-county offerings (age-40 individual scenario used as
-- the enumeration basis so every plan appears exactly once per county
-- where it is offered). Shares are in percentage points, so the HHI
-- reported here ranges from 0 to 10 000 following the DOJ convention;
-- 2 500+ is the "highly concentrated" threshold.

with offerings as (

    select
        counties.state_code,
        plans.issuer_name,
        count(*) as plan_county_offerings
    from main_marts.fct_qhp_premiums as premiums
    inner join
        main_marts.dim_qhp_plan as plans using (plan_id)
    inner join
        main_marts.dim_county as counties using (fips_county_code)
    where
        plans.product = 'medical'
        and plans.market = 'individual'
        and premiums.scenario = 'individual_age_40'
    group by 1, 2

),

state_totals as (

    select
        state_code,
        sum(plan_county_offerings) as total_offerings
    from offerings
    group by 1

),

issuer_shares as (

    select
        offerings.state_code,
        offerings.issuer_name,
        offerings.plan_county_offerings,
        cast(offerings.plan_county_offerings as double)
        / state_totals.total_offerings as share
    from offerings
    inner join state_totals using (state_code)

)

select
    state_code,
    count(*) as issuers,
    round(sum(pow(share * 100, 2)), 0) as hhi,
    max(share) as top_issuer_share
from issuer_shares
group by 1
order by hhi desc
