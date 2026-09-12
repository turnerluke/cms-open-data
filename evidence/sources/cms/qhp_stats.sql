select
    (select count(*) from main_marts.dim_qhp_plan) as plans,
    (
        select count(*) from main_marts.dim_qhp_plan
        where product = 'medical' and market = 'individual'
    ) as individual_medical_plans,
    (
        select count(*) from main_marts.dim_qhp_plan
        where product = 'dental' and market = 'individual'
    ) as individual_dental_plans,
    (
        select count(*) from main_marts.dim_qhp_plan
        where market = 'shop'
    ) as shop_plans,
    (
        select count(distinct issuer_name)
        from main_marts.dim_qhp_plan
    ) as issuers,
    (
        select count(distinct issuer_name) from main_marts.dim_qhp_plan
        where product = 'medical' and market = 'individual'
    ) as individual_medical_issuers,
    (
        select count(distinct state_code) from main_marts.dim_county
    ) as states,
    (select count(*) from main_marts.dim_county) as counties,
    (
        select count(*) from main_marts.fct_qhp_premiums
    ) as premium_rows,
    (
        select count(*) from main_marts.fct_qhp_cost_sharing
    ) as cost_sharing_rows,
    (select max(as_of) from main_marts.dim_qhp_plan) as plan_as_of,
    (select max(plan_year) from main_marts.dim_qhp_plan) as plan_year
