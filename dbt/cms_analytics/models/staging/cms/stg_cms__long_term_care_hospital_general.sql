with source as (

    select * from {{ source('cms_raw', 'cms_long_term_care_hospital_general') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as upper(trim()) to match every
        -- other staging model that carries one. Every LTCH CCN in
        -- the current vintage is six digits (no letter-suffixed
        -- CCNs), reflecting that long-term care hospitals are
        -- freestanding facilities rather than units embedded in a
        -- host acute hospital.
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(provider_name) as provider_name,

        -- address. This file marks missing values with a literal
        -- `-` placeholder rather than a blank: address_line_2 is
        -- `-` in every one of the 311 rows; nulled alongside blanks.
        trim(address_line_1) as address_line_1,
        nullif(nullif(trim(address_line_2), ''), '-') as address_line_2,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        trim(countyparish) as county,
        trim(telephone_number) as telephone_number,
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
        ) as certification_date,

        -- capacity. 5 of 311 rows carry the file's `-` placeholder,
        -- which `try_cast` turns into NULL.
        try_cast(total_number_of_beds as int) as total_number_of_beds

    from source

)

select * from renamed
