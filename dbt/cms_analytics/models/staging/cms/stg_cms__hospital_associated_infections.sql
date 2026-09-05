with source as (

    select * from {{ source('cms_raw', 'cms_hospital_associated_infections') }}

),

renamed as (

    select
        -- identifiers
        facility_id,
        trim(facility_name) as facility_name,

        -- address
        trim(address) as address,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        trim(countyparish) as county,
        trim(telephone_number) as telephone_number,

        -- measure
        trim(measure_id) as measure_id,
        trim(measure_name) as measure_name,
        nullif(trim(compared_to_national), 'Not Available') as compared_to_national,

        -- results ('Not Available' becomes null)
        try_cast(score as decimal(10, 3)) as score,
        nullif(trim(footnote), '') as footnote,

        -- measurement period
        cast(try_strptime(start_date, '%m/%d/%Y') as date) as start_date,
        cast(try_strptime(end_date, '%m/%d/%Y') as date) as end_date

    from source

)

select * from renamed
