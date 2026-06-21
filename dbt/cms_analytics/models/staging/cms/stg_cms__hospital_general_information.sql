with source as (

    select * from {{ source('cms_raw', 'cms_hospital_general_information') }}

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

        -- classification
        trim(hospital_type) as hospital_type,
        trim(hospital_ownership) as hospital_ownership,
        case
            when emergency_services = 'Yes' then true
            when emergency_services = 'No' then false
        end as emergency_services,
        case
            when meets_criteria_for_birthing_friendly_designation = 'Y' then true
        end as meets_birthing_friendly_criteria,

        -- overall rating (1-5; 'Not Available' becomes null)
        try_cast(hospital_overall_rating as int) as hospital_overall_rating,
        nullif(trim(hospital_overall_rating_footnote), '') as hospital_overall_rating_footnote,

        -- mortality measures
        try_cast(mort_group_measure_count as int) as mort_group_measure_count,
        try_cast(count_of_facility_mort_measures as int) as count_of_facility_mort_measures,
        try_cast(count_of_mort_measures_better as int) as count_of_mort_measures_better,
        try_cast(count_of_mort_measures_no_different as int) as count_of_mort_measures_no_different,
        try_cast(count_of_mort_measures_worse as int) as count_of_mort_measures_worse,
        nullif(trim(mort_group_footnote), '') as mort_group_footnote,

        -- safety measures
        try_cast(safety_group_measure_count as int) as safety_group_measure_count,
        try_cast(count_of_facility_safety_measures as int) as count_of_facility_safety_measures,
        try_cast(count_of_safety_measures_better as int) as count_of_safety_measures_better,
        try_cast(count_of_safety_measures_no_different as int) as count_of_safety_measures_no_different,
        try_cast(count_of_safety_measures_worse as int) as count_of_safety_measures_worse,
        nullif(trim(safety_group_footnote), '') as safety_group_footnote,

        -- readmission measures
        try_cast(readm_group_measure_count as int) as readm_group_measure_count,
        try_cast(count_of_facility_readm_measures as int) as count_of_facility_readm_measures,
        try_cast(count_of_readm_measures_better as int) as count_of_readm_measures_better,
        try_cast(count_of_readm_measures_no_different as int) as count_of_readm_measures_no_different,
        try_cast(count_of_readm_measures_worse as int) as count_of_readm_measures_worse,
        nullif(trim(readm_group_footnote), '') as readm_group_footnote,

        -- patient experience measures
        try_cast(pt_exp_group_measure_count as int) as pt_exp_group_measure_count,
        try_cast(count_of_facility_pt_exp_measures as int) as count_of_facility_pt_exp_measures,
        nullif(trim(pt_exp_group_footnote), '') as pt_exp_group_footnote,

        -- timely & effective care measures
        try_cast(te_group_measure_count as int) as te_group_measure_count,
        try_cast(count_of_facility_te_measures as int) as count_of_facility_te_measures,
        nullif(trim(te_group_footnote), '') as te_group_footnote

    from source

)

select * from renamed
