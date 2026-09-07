with source as (

    select * from {{ source('cms_raw', 'cms_hospice_cahps_provider') }}

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

        -- score is a bottom-box / middle-box / top-box percentage
        -- (measure_code suffix `_BBV` / `_MBV` / `_TBV`); the
        -- `SUMMARY_STAR_RATING` row carries a star value instead
        nullif(trim(score), '') as score,

        -- star_rating carries '1'..'5' for the summary rating row,
        -- 'Not Applicable' / 'Not Available' for the others → null
        -- when non-numeric
        try_cast(nullif(trim(star_rating), '') as int) as star_rating,
        nullif(trim(footnote), '') as footnote,

        -- date range, verbatim (e.g. `10/01/2023-09/30/2025`; a
        -- single value per vintage)
        trim(date) as measure_date_range

    from source

)

select * from renamed
