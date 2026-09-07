with source as (

    select * from {{ source('cms_raw', 'cms_hospice_cahps_national') }}

),

renamed as (

    select
        -- one national benchmark row per CAHPS measure
        trim(measure_code) as measure_code,
        trim(measure_name) as measure_name,

        -- national bottom/middle/top-box percentage per measure
        nullif(trim(score), '') as score,
        nullif(trim(footnote), '') as footnote,

        -- date range, verbatim (e.g. `10/01/2023-09/30/2025`; a
        -- single value per vintage) — matches sibling
        -- stg_cms__hospice_cahps_provider; parsing deferred to marts
        trim(date) as measure_date_range

    from source

)

select * from renamed
