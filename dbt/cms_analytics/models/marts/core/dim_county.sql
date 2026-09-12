with individual_medical as (

    select
        fips_county_code,
        state_code,
        county_name
    from {{ ref('stg_cms__qhp_landscape_individual_medical_2026') }}

),

individual_dental as (

    select
        fips_county_code,
        state_code,
        county_name
    from {{ ref('stg_cms__qhp_landscape_individual_dental_2026') }}

),

shop_medical as (

    select
        fips_county_code,
        state_code,
        county_name
    from {{ ref('stg_cms__qhp_landscape_shop_medical_2026') }}

),

shop_dental as (

    select
        fips_county_code,
        state_code,
        county_name
    from {{ ref('stg_cms__qhp_landscape_shop_dental_2026') }}

),

unioned as (

    select * from individual_medical
    union all
    select * from individual_dental
    union all
    select * from shop_medical
    union all
    select * from shop_dental

),

-- `state_code` and `county_name` are constant per FIPS across all four
-- QHP files in the PY2026 vintage (zero collisions verified), so
-- `any_value` collapses deterministically without a tie-break.
collapsed as (

    select
        fips_county_code,
        any_value(state_code) as state_code,
        any_value(county_name) as county_name
    from unioned
    group by 1

),

final as (

    select
        c.*,
        -- Snapshot vintage: max `modified` across the four QHP dataset
        -- keys — same pattern as `dim_qhp_plan.as_of`. Scalar subquery
        -- so a missing sidecar surfaces as NULL rather than dropping
        -- rows.
        (
            select max(vintages.modified) as modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key in (
                'qhp_landscape_individual_medical_2026',
                'qhp_landscape_individual_dental_2026',
                'qhp_landscape_shop_medical_2026',
                'qhp_landscape_shop_dental_2026'
            )
        ) as as_of
    from collapsed as c

)

select * from final
