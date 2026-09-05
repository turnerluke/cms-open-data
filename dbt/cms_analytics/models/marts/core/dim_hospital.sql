with staged as (

    select * from {{ ref('stg_cms__hospital_general_information') }}

),

final as (

    select
        -- identifiers
        facility_id as ccn,
        facility_name as hospital_name,

        -- address
        address,
        city,
        state,
        zip5,
        county,
        telephone_number,

        -- classification
        hospital_type,
        hospital_ownership,
        emergency_services,
        meets_birthing_friendly_criteria,

        -- quality
        hospital_overall_rating
    from staged

)

select * from final
