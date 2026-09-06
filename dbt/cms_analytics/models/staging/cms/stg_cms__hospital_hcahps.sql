with source as (

    select * from {{ source('cms_raw', 'cms_hospital_hcahps') }}

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
        trim(hcahps_measure_id) as measure_id,
        trim(hcahps_question) as question,
        trim(hcahps_answer_description) as answer_description,

        -- results ('Not Available' / 'Not Applicable' become null)
        try_cast(patient_survey_star_rating as int)
            as patient_survey_star_rating,
        nullif(trim(patient_survey_star_rating_footnote), '')
            as patient_survey_star_rating_footnote,
        try_cast(hcahps_answer_percent as int) as answer_percent,
        nullif(trim(hcahps_answer_percent_footnote), '')
            as answer_percent_footnote,
        try_cast(hcahps_linear_mean_value as int) as linear_mean_value,

        -- survey administration
        try_cast(number_of_completed_surveys as int)
            as number_of_completed_surveys,
        nullif(trim(number_of_completed_surveys_footnote), '')
            as number_of_completed_surveys_footnote,
        try_cast(survey_response_rate_percent as int)
            as survey_response_rate_percent,
        nullif(trim(survey_response_rate_percent_footnote), '')
            as survey_response_rate_percent_footnote,

        -- measurement period
        cast(try_strptime(start_date, '%m/%d/%Y') as date) as start_date,
        cast(try_strptime(end_date, '%m/%d/%Y') as date) as end_date

    from source

)

select * from renamed
