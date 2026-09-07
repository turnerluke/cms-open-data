with source as (

    select * from {{ source('cms_raw', 'cms_nursing_home_quality_measures_mds') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as in
        -- stg_cms__nursing_home_provider_info
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(provider_name) as provider_name,

        -- address
        trim(provider_address) as address,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,

        -- measure
        trim(measure_code) as measure_code,
        trim(measure_description) as measure_description,
        trim(resident_type) as resident_type,

        -- quarterly scores (percentages; empty string becomes null)
        try_cast(q1_measure_score as double) as q1_measure_score,
        nullif(trim(footnote_for_q1_measure_score), '') as q1_measure_score_footnote,
        try_cast(q2_measure_score as double) as q2_measure_score,
        nullif(trim(footnote_for_q2_measure_score), '') as q2_measure_score_footnote,
        try_cast(q3_measure_score as double) as q3_measure_score,
        nullif(trim(footnote_for_q3_measure_score), '') as q3_measure_score_footnote,
        try_cast(q4_measure_score as double) as q4_measure_score,
        nullif(trim(footnote_for_q4_measure_score), '') as q4_measure_score_footnote,
        try_cast(four_quarter_average_score as double) as four_quarter_average_score,
        nullif(trim(footnote_for_four_quarter_average_score), '') as four_quarter_average_score_footnote,
        case
            when used_in_quality_measure_five_star_rating = 'Y' then true
            when used_in_quality_measure_five_star_rating = 'N' then false
        end as used_in_five_star_rating,

        -- measurement period (quarter range, e.g. '2025Q2-2026Q1')
        trim(measure_period) as measure_period,

        -- metadata
        trim(location) as location_address,
        try_cast(processing_date as date) as processing_date

    from source

)

select * from renamed
