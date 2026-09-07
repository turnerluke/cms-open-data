with source as (

    select * from {{ source('cms_raw', 'cms_nursing_home_health_deficiencies') }}

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

        -- deficiency
        try_cast(survey_date as date) as survey_date,
        trim(survey_type) as survey_type,
        trim(deficiency_prefix) as deficiency_prefix,
        trim(deficiency_category) as deficiency_category,
        -- zero-padded four-digit F-tag, kept as text
        deficiency_tag_number as deficiency_tag,
        trim(deficiency_description) as deficiency_description,
        scope_severity_code,

        -- correction
        trim(deficiency_corrected) as correction_status,
        -- empty string (no correction date yet) becomes null
        try_cast(correction_date as date) as correction_date,

        -- citation context
        try_cast(inspection_cycle as int) as inspection_cycle,
        case
            when standard_deficiency = 'Y' then true
            when standard_deficiency = 'N' then false
        end as is_standard_deficiency,
        case
            when complaint_deficiency = 'Y' then true
            when complaint_deficiency = 'N' then false
        end as is_complaint_deficiency,
        case
            when infection_control_inspection_deficiency = 'Y' then true
            when infection_control_inspection_deficiency = 'N' then false
        end as is_infection_control_deficiency,
        case
            when citation_under_idr = 'Y' then true
            when citation_under_idr = 'N' then false
        end as is_citation_under_idr,
        case
            when citation_under_iidr = 'Y' then true
            when citation_under_iidr = 'N' then false
        end as is_citation_under_iidr,

        -- metadata
        trim(location) as location_address,
        try_cast(processing_date as date) as processing_date

    from source

)

select * from renamed
