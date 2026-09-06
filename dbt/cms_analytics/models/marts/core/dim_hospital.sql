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
        hospital_overall_rating,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospital_general_information'
        ) as as_of
    from staged

)

select * from final
