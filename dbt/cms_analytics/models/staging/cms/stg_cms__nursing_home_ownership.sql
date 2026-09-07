with source as (

    select * from {{ source('cms_raw', 'cms_nursing_home_ownership') }}

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

        -- owner
        trim(role_played_by_owner_or_manager_in_facility) as owner_role,
        -- 'Individual' / 'Organization'; empty string becomes null
        nullif(trim(owner_type), '') as owner_type,
        -- null on 'Ownership Data Not Available' rows
        nullif(trim(owner_name), '') as owner_name,
        -- '5%' → 5; 'NOT APPLICABLE' / 'NO PERCENTAGE PROVIDED' and
        -- empty strings become null via try_cast
        try_cast(rtrim(ownership_percentage, '%') as int) as ownership_percentage,
        -- raw 'since MM/DD/YYYY'; 'NO DATE PROVIDED' and empty
        -- strings become null via try_strptime
        cast(try_strptime(association_date, 'since %m/%d/%Y') as date) as association_date,

        -- metadata
        trim(location) as location_address,
        try_cast(processing_date as date) as processing_date

    from source

)

select * from renamed
