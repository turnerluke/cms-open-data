with source as (

    select * from {{ source('cms_raw', 'cms_hospital_value_based_purchasing_total') }}

),

renamed as (

    select
        -- fiscal year — constant `'2026'` across the file; kept as a
        -- string to match the `plan_year` convention elsewhere and to
        -- support future stacked vintages verbatim
        trim(fiscal_year) as fiscal_year,

        -- identifiers
        -- CCN join key, conformed as in
        -- stg_cms__hospital_general_information
        upper(trim(facility_id)) as facility_id,
        trim(facility_name) as facility_name,

        -- address
        trim(address) as address,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        trim(countyparish) as county,

        -- domain scores — each of the four VBP domains ships an
        -- unweighted (0–100) and a weighted (share of the total
        -- score) column. `'Not Available'` sentinels — most on
        -- clinical outcomes (68), safety (55) and person &
        -- community engagement (32); efficiency has 1 — become
        -- `NULL` via try_cast.
        try_cast(unweighted_normalized_clinical_outcomes_domain_score as decimal(18, 12))
            as unweighted_clinical_outcomes_score,
        try_cast(weighted_normalized_clinical_outcomes_domain_score as decimal(18, 12))
            as weighted_clinical_outcomes_score,
        try_cast(unweighted_person_and_community_engagement_domain_score as decimal(18, 12))
            as unweighted_person_and_community_engagement_score,
        try_cast(weighted_person_and_community_engagement_domain_score as decimal(18, 12))
            as weighted_person_and_community_engagement_score,
        try_cast(unweighted_normalized_safety_domain_score as decimal(18, 12))
            as unweighted_safety_score,
        try_cast(weighted_safety_domain_score as decimal(18, 12))
            as weighted_safety_score,
        try_cast(unweighted_normalized_efficiency_and_cost_reduction_domain_score as decimal(18, 12))
            as unweighted_efficiency_and_cost_reduction_score,
        try_cast(weighted_efficiency_and_cost_reduction_domain_score as decimal(18, 12))
            as weighted_efficiency_and_cost_reduction_score,

        -- total performance score — fully numerically castable in
        -- this vintage (zero `'Not Available'` sentinels), so
        -- `not_null` is safe.
        try_cast(total_performance_score as decimal(18, 12)) as total_performance_score

    from source

)

select * from renamed
