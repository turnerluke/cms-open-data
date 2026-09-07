with source as (

    select * from {{ source('cms_raw', 'cms_nursing_home_penalties') }}

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

        -- penalty
        try_cast(penalty_date as date) as penalty_date,
        trim(penalty_type) as penalty_type,

        -- fine detail ('Fine' rows only; empty string becomes null)
        nullif(trim(fine_id), '') as fine_id,
        try_cast(fine_amount as decimal(12, 2)) as fine_amount,

        -- payment-denial detail ('Payment Denial' rows only)
        try_cast(payment_denial_start_date as date) as payment_denial_start_date,
        try_cast(payment_denial_length_in_days as int) as payment_denial_length_in_days,

        -- metadata
        trim(location) as location_address,
        try_cast(processing_date as date) as processing_date

    from source

)

select * from renamed
