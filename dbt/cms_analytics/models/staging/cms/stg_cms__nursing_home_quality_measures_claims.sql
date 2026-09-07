with source as (

    select * from {{ source('cms_raw', 'cms_nursing_home_quality_measures_claims') }}

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

        -- scores (empty string becomes null)
        try_cast(adjusted_score as double) as adjusted_score,
        try_cast(observed_score as double) as observed_score,
        try_cast(expected_score as double) as expected_score,
        nullif(trim(footnote_for_score), '') as score_footnote,
        case
            when used_in_quality_measure_five_star_rating = 'Y' then true
            when used_in_quality_measure_five_star_rating = 'N' then false
        end as used_in_five_star_rating,

        -- measurement period (date range, e.g. '20250101-20251231')
        trim(measure_period) as measure_period,

        -- metadata
        trim(location) as location_address,
        try_cast(processing_date as date) as processing_date

    from source

)

select * from renamed
