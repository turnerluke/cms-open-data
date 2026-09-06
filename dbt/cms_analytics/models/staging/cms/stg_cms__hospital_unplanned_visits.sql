with source as (

    select * from {{ source('cms_raw', 'cms_hospital_unplanned_visits') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as in
        -- stg_cms__hospital_general_information
        upper(trim(facility_id)) as facility_id,
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

        -- results ('Not Available'/'Not Applicable' become null)
        try_cast(denominator as int) as denominator,
        try_cast(score as decimal(10, 3)) as score,
        try_cast(lower_estimate as decimal(10, 3)) as lower_estimate,
        try_cast(higher_estimate as decimal(10, 3)) as higher_estimate,
        try_cast(number_of_patients as int) as number_of_patients,
        try_cast(number_of_patients_returned as int) as number_of_patients_returned,
        nullif(trim(footnote), '') as footnote,

        -- measurement period
        cast(try_strptime(start_date, '%m/%d/%Y') as date) as start_date,
        cast(try_strptime(end_date, '%m/%d/%Y') as date) as end_date

    from source

)

select * from renamed
