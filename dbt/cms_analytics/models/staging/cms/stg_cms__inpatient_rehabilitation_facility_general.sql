with source as (

    select * from {{ source('cms_raw', 'cms_inpatient_rehabilitation_facility_general') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as upper(trim()) to match every
        -- other staging model that carries one. IRF CCNs are six
        -- alphanumeric characters: 410 rows are freestanding
        -- rehab hospitals whose CCN is fully numeric, and the
        -- remaining 812 rows are IRF units embedded in an acute
        -- hospital, encoded with a letter in the third position
        -- (`T` for standard rehab units, `R` for critical-access
        -- rehab units; e.g. `01T011`). The suffix is kept verbatim
        -- so the key round-trips against other Care Compare files.
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(provider_name) as provider_name,

        -- address. This file marks missing values with a literal
        -- `-` placeholder rather than a blank: address_line_2 is
        -- `-` in 1,153 of 1,222 rows (69 carry a real value) and
        -- telephone_number in 4; both are nulled alongside blanks.
        trim(address_line_1) as address_line_1,
        nullif(nullif(trim(address_line_2), ''), '-') as address_line_2,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        trim(countyparish) as county,
        nullif(nullif(trim(telephone_number), ''), '-') as telephone_number,
        trim(cms_region) as cms_region,

        -- classification
        trim(ownership_type) as ownership_type,
        -- CMS ships this as `MM/DD/YYYY` text; `try_cast(... as date)`
        -- silently returns NULL for that format, so parse with
        -- `try_strptime`, which yields NULL rather than raising on
        -- any malformed value a future publish might introduce.
        -- Every value in the current vintage is well-formed.
        cast(
            try_strptime(nullif(trim(certification_date), ''), '%m/%d/%Y') as date
        ) as certification_date

    from source

)

select * from renamed
