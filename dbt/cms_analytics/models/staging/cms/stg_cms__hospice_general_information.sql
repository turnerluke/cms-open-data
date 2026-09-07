with source as (

    select * from {{ source('cms_raw', 'cms_hospice_general_information') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as upper(trim()) to match every
        -- other staging model that carries one. Hospice CCNs are six
        -- alphanumeric characters, some carrying a letter in the
        -- third position (e.g. `05A123`); no numeric twin exists for
        -- the letter-bearing CCNs in this file.
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(facility_name) as facility_name,

        -- address (address_line_2 is typically empty; kept as-is)
        trim(address_line_1) as address_line_1,
        nullif(trim(address_line_2), '') as address_line_2,
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
        -- `strptime` instead. Every value in the current vintage is
        -- well-formed; guard against empty strings defensively so a
        -- future publish doesn't crash the build.
        cast(
            strptime(nullif(trim(certification_date), ''), '%m/%d/%Y') as date
        ) as certification_date

    from source

)

select * from renamed
