with staged as (

    select * from {{ ref('stg_cms__hospital_value_based_purchasing_total') }}

),

final as (

    select
        -- identifiers
        facility_id as ccn,
        fiscal_year,

        -- domain scores — each of the four VBP domains ships both an
        -- unweighted (0–100) and a weighted (share of the 100-point
        -- total) score. NULLs arrive from the staging `try_cast` of
        -- CMS's `'Not Available'` sentinels; the four domains lose
        -- roughly 68 / 32 / 55 / 1 rows respectively.
        unweighted_clinical_outcomes_score,
        weighted_clinical_outcomes_score,
        unweighted_person_and_community_engagement_score,
        weighted_person_and_community_engagement_score,
        unweighted_safety_score,
        weighted_safety_score,
        unweighted_efficiency_and_cost_reduction_score,
        weighted_efficiency_and_cost_reduction_score,

        -- overall — fully numeric in this vintage (no `'Not
        -- Available'` sentinels), so `not_null` is safe.
        total_performance_score,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospital_value_based_purchasing_total'
        ) as as_of
    from staged

)

select * from final
