with hcahps as (

    select
        facility_id as ccn,
        'hcahps' as measure_domain,
        measure_id,
        question as measure_name,
        -- each HCAHPS measure_id populates exactly one result family
        -- (star rating, answer percent, or linear mean score), so the
        -- coalesce picks the single populated value for the row
        cast(
            coalesce(patient_survey_star_rating, answer_percent, linear_mean_value)
            as decimal(10, 3)
        ) as score,
        number_of_completed_surveys as denominator,
        cast(null as varchar) as compared_to_national,
        start_date,
        end_date,
        -- per-domain snapshot vintage: upstream `modified` date of
        -- each source file, kept as the last column in every branch so
        -- the union stays positionally aligned
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospital_hcahps'
        ) as as_of
    from {{ ref('stg_cms__hospital_hcahps') }}

),

complications_deaths as (

    select
        facility_id as ccn,
        'complications_deaths' as measure_domain,
        measure_id,
        measure_name,
        score,
        denominator,
        compared_to_national,
        start_date,
        end_date,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospital_complications_deaths'
        ) as as_of
    from {{ ref('stg_cms__hospital_complications_deaths') }}

),

infections as (

    select
        facility_id as ccn,
        'infections' as measure_domain,
        measure_id,
        measure_name,
        score,
        -- HAI publishes eligible-case counts as their own measure rows
        -- (`HAI_*_ELIGCASES`), not as a per-row denominator column
        cast(null as int) as denominator,
        compared_to_national,
        start_date,
        end_date,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospital_associated_infections'
        ) as as_of
    from {{ ref('stg_cms__hospital_associated_infections') }}

),

unplanned_visits as (

    select
        facility_id as ccn,
        'unplanned_visits' as measure_domain,
        measure_id,
        measure_name,
        score,
        denominator,
        compared_to_national,
        start_date,
        end_date,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospital_unplanned_visits'
        ) as as_of
    from {{ ref('stg_cms__hospital_unplanned_visits') }}

),

final as (

    -- rows whose score is null (suppressed / not available upstream)
    -- are kept so measure coverage per hospital stays analyzable
    select * from hcahps
    union all
    select * from complications_deaths
    union all
    select * from infections
    union all
    select * from unplanned_visits

)

select * from final
