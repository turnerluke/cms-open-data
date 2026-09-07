with mds as (

    select
        ccn,
        'mds' as measure_source,
        measure_code,
        measure_description as measure_name,
        resident_type,
        -- headline score only: the four quarterly scores (suppressed
        -- ~22% of rows vs ~4% for the average) stay in staging
        four_quarter_average_score as score,
        four_quarter_average_score_footnote as score_footnote,
        used_in_five_star_rating,
        measure_period,
        -- per-source snapshot vintage: upstream `modified` date of
        -- each source file, kept as the last column in every branch so
        -- the union stays positionally aligned
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'nursing_home_quality_measures_mds'
        ) as as_of
    from {{ ref('stg_cms__nursing_home_quality_measures_mds') }}

),

claims as (

    select
        ccn,
        'claims' as measure_source,
        measure_code,
        measure_description as measure_name,
        resident_type,
        -- the risk-adjusted score is the headline number CMS displays;
        -- the observed/expected components stay in staging
        adjusted_score as score,
        score_footnote,
        used_in_five_star_rating,
        measure_period,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'nursing_home_quality_measures_claims'
        ) as as_of
    from {{ ref('stg_cms__nursing_home_quality_measures_claims') }}

),

final as (

    -- rows whose score is null (suppressed upstream) are kept so
    -- measure coverage per nursing home stays analyzable
    select * from mds
    union all
    select * from claims

)

select * from final
