with source as (

    select * from {{ source('cms_raw', 'cms_hospice_provider_quality') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as in
        -- stg_cms__hospice_general_information
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(facility_name) as facility_name,

        -- address (address_line_2 is typically empty)
        trim(address_line_1) as address_line_1,
        nullif(trim(address_line_2), '') as address_line_2,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        trim(countyparish) as county,
        trim(telephone_number) as telephone_number,
        trim(cms_region) as cms_region,

        -- measure
        trim(measure_code) as measure_code,
        trim(measure_name) as measure_name,

        -- score arrives as text — HIS/HCI measures ship counts,
        -- percentages, and percentile ranks side-by-side under the
        -- same column so casting is a downstream (mart) concern.
        nullif(trim(score), '') as score,
        nullif(trim(footnote), '') as footnote,

        -- measurement period, verbatim (e.g. `01/01/2024 - 12/31/2024`
        -- or `10/01/2024 - 09/30/2025`; the ranges differ by measure
        -- family). Kept verbatim here — date parsing happens in
        -- marts, matching how stg_cms__nursing_home_quality_measures*
        -- kept `measure_period` verbatim.
        trim(measure_date_range) as measure_date_range

    from source

)

select * from renamed
