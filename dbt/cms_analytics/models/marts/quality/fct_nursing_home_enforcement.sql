with deficiencies as (

    select
        ccn,
        'deficiency' as action_type,
        survey_date as action_date,
        -- per-type disambiguator within (ccn, action_type,
        -- action_date): prefix + tag for citations, fine_id (or the
        -- penalty_type for id-less payment denials) for penalties
        deficiency_prefix || deficiency_tag as detail_key,

        -- deficiency detail (null on penalty rows)
        deficiency_prefix,
        deficiency_tag,
        deficiency_description,
        scope_severity_code,
        is_standard_deficiency,
        is_complaint_deficiency,
        correction_date,

        -- penalty detail (null on deficiency rows)
        cast(null as varchar) as penalty_type,
        cast(null as varchar) as fine_id,
        cast(null as decimal(12, 2)) as fine_amount,
        cast(null as date) as payment_denial_start_date,
        cast(null as int) as payment_denial_length_in_days,

        -- per-source snapshot vintage: upstream `modified` date of
        -- each source file, kept as the last column in every branch so
        -- the union stays positionally aligned
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'nursing_home_health_deficiencies'
        ) as as_of
    from {{ ref('stg_cms__nursing_home_health_deficiencies') }}

),

penalties as (

    select
        ccn,
        'penalty' as action_type,
        penalty_date as action_date,
        coalesce(fine_id, penalty_type) as detail_key,

        cast(null as varchar) as deficiency_prefix,
        cast(null as varchar) as deficiency_tag,
        cast(null as varchar) as deficiency_description,
        cast(null as varchar) as scope_severity_code,
        cast(null as boolean) as is_standard_deficiency,
        cast(null as boolean) as is_complaint_deficiency,
        cast(null as date) as correction_date,

        penalty_type,
        fine_id,
        fine_amount,
        payment_denial_start_date,
        payment_denial_length_in_days,

        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'nursing_home_penalties'
        ) as as_of
    from {{ ref('stg_cms__nursing_home_penalties') }}

),

final as (

    select * from deficiencies
    union all
    select * from penalties

)

select * from final
