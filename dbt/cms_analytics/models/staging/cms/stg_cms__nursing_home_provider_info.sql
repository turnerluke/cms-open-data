with source as (

    select * from {{ source('cms_raw', 'cms_nursing_home_provider_info') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as upper(trim()) as in
        -- stg_cms__hospital_general_information. Nursing-home CCNs are
        -- six alphanumeric characters (some carry a letter in the
        -- third position, e.g. `01A234`).
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(provider_name) as provider_name,
        trim(legal_business_name) as legal_business_name,

        -- address
        trim(provider_address) as address,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        provider_ssa_county_code as ssa_county_code,
        trim(countyparish) as county,
        trim(telephone_number) as telephone_number,

        -- classification
        case
            when urban = 'Y' then true
            when urban = 'N' then false
        end as is_urban,
        trim(ownership_type) as ownership_type,
        trim(provider_type) as provider_type,
        case
            when provider_resides_in_hospital = 'Y' then true
            when provider_resides_in_hospital = 'N' then false
        end as resides_in_hospital,
        try_cast(date_first_approved_to_provide_medicare_and_medicaid_services as date) as first_approved_date,
        case
            when continuing_care_retirement_community = 'Y' then true
            when continuing_care_retirement_community = 'N' then false
        end as is_continuing_care_retirement_community,
        -- 'SFF' / 'SFF Candidate'; empty string (most homes) becomes null
        nullif(trim(special_focus_status), '') as special_focus_status,

        -- capacity
        try_cast(number_of_certified_beds as int) as number_of_certified_beds,
        try_cast(average_number_of_residents_per_day as double) as average_residents_per_day,
        nullif(trim(average_number_of_residents_per_day_footnote), '') as average_residents_per_day_footnote,

        -- chain affiliation (nulls for independent homes)
        nullif(trim(chain_name), '') as chain_name,
        try_cast(chain_id as int) as chain_id,
        try_cast(number_of_facilities_in_chain as int) as number_of_facilities_in_chain,
        try_cast(chain_average_overall_5star_rating as double) as chain_average_overall_rating,
        try_cast(chain_average_health_inspection_rating as double) as chain_average_health_inspection_rating,
        try_cast(chain_average_staffing_rating as double) as chain_average_staffing_rating,
        try_cast(chain_average_qm_rating as double) as chain_average_qm_rating,

        -- status flags
        case
            when abuse_icon = 'Y' then true
            when abuse_icon = 'N' then false
        end as has_abuse_icon,
        case
            when most_recent_health_inspection_more_than_2_years_ago = 'Y' then true
            when most_recent_health_inspection_more_than_2_years_ago = 'N' then false
        end as last_inspection_more_than_2_years_ago,
        case
            when provider_changed_ownership_in_last_12_months = 'Y' then true
            when provider_changed_ownership_in_last_12_months = 'N' then false
        end as changed_ownership_in_last_12_months,
        -- 'Resident' / 'Both' / 'None' in the current vintage
        trim(with_a_resident_and_family_council) as resident_and_family_council,
        -- 'Yes' / 'Partial' / 'Data Not Available' kept verbatim
        trim(automatic_sprinkler_systems_in_all_required_areas) as automatic_sprinkler_systems,

        -- star ratings (1-5; empty string becomes null)
        try_cast(overall_rating as int) as overall_rating,
        nullif(trim(overall_rating_footnote), '') as overall_rating_footnote,
        try_cast(health_inspection_rating as int) as health_inspection_rating,
        nullif(trim(health_inspection_rating_footnote), '') as health_inspection_rating_footnote,
        try_cast(qm_rating as int) as qm_rating,
        nullif(trim(qm_rating_footnote), '') as qm_rating_footnote,
        try_cast(longstay_qm_rating as int) as longstay_qm_rating,
        nullif(trim(longstay_qm_rating_footnote), '') as longstay_qm_rating_footnote,
        try_cast(shortstay_qm_rating as int) as shortstay_qm_rating,
        nullif(trim(shortstay_qm_rating_footnote), '') as shortstay_qm_rating_footnote,
        try_cast(staffing_rating as int) as staffing_rating,
        nullif(trim(staffing_rating_footnote), '') as staffing_rating_footnote,
        nullif(trim(reported_staffing_footnote), '') as reported_staffing_footnote,
        nullif(trim(physical_therapist_staffing_footnote), '') as physical_therapist_staffing_footnote,

        -- reported staffing (hours per resident per day)
        try_cast(reported_nurse_aide_staffing_hours_per_resident_per_day as double)
            as reported_nurse_aide_staffing_hours_per_resident_per_day,
        try_cast(reported_lpn_staffing_hours_per_resident_per_day as double)
            as reported_lpn_staffing_hours_per_resident_per_day,
        try_cast(reported_rn_staffing_hours_per_resident_per_day as double)
            as reported_rn_staffing_hours_per_resident_per_day,
        try_cast(reported_licensed_staffing_hours_per_resident_per_day as double)
            as reported_licensed_staffing_hours_per_resident_per_day,
        try_cast(reported_total_nurse_staffing_hours_per_resident_per_day as double)
            as reported_total_nurse_staffing_hours_per_resident_per_day,
        try_cast(total_number_of_nurse_staff_hours_per_resident_per_day_on_t_4a14 as double)
            as reported_weekend_total_nurse_staffing_hours_per_resident_per_day,
        try_cast(registered_nurse_hours_per_resident_per_day_on_the_weekend as double)
            as reported_weekend_rn_staffing_hours_per_resident_per_day,
        try_cast(reported_physical_therapist_staffing_hours_per_resident_per_day as double)
            as reported_physical_therapist_staffing_hours_per_resident_per_day,

        -- turnover
        try_cast(total_nursing_staff_turnover as double) as total_nursing_staff_turnover_pct,
        nullif(trim(total_nursing_staff_turnover_footnote), '') as total_nursing_staff_turnover_footnote,
        try_cast(registered_nurse_turnover as double) as registered_nurse_turnover_pct,
        nullif(trim(registered_nurse_turnover_footnote), '') as registered_nurse_turnover_footnote,
        try_cast(number_of_administrators_who_have_left_the_nursing_home as int) as administrators_left_count,
        nullif(trim(administrator_turnover_footnote), '') as administrator_turnover_footnote,

        -- case-mix adjusted staffing
        try_cast(nursing_casemix_index as double) as nursing_casemix_index,
        try_cast(nursing_casemix_index_ratio as double) as nursing_casemix_index_ratio,
        try_cast(casemix_nurse_aide_staffing_hours_per_resident_per_day as double)
            as casemix_nurse_aide_staffing_hours_per_resident_per_day,
        try_cast(casemix_lpn_staffing_hours_per_resident_per_day as double)
            as casemix_lpn_staffing_hours_per_resident_per_day,
        try_cast(casemix_rn_staffing_hours_per_resident_per_day as double)
            as casemix_rn_staffing_hours_per_resident_per_day,
        try_cast(casemix_total_nurse_staffing_hours_per_resident_per_day as double)
            as casemix_total_nurse_staffing_hours_per_resident_per_day,
        try_cast(casemix_weekend_total_nurse_staffing_hours_per_resident_per_day as double)
            as casemix_weekend_total_nurse_staffing_hours_per_resident_per_day,
        try_cast(adjusted_nurse_aide_staffing_hours_per_resident_per_day as double)
            as adjusted_nurse_aide_staffing_hours_per_resident_per_day,
        try_cast(adjusted_lpn_staffing_hours_per_resident_per_day as double)
            as adjusted_lpn_staffing_hours_per_resident_per_day,
        try_cast(adjusted_rn_staffing_hours_per_resident_per_day as double)
            as adjusted_rn_staffing_hours_per_resident_per_day,
        try_cast(adjusted_total_nurse_staffing_hours_per_resident_per_day as double)
            as adjusted_total_nurse_staffing_hours_per_resident_per_day,
        try_cast(adjusted_weekend_total_nurse_staffing_hours_per_resident_per_day as double)
            as adjusted_weekend_total_nurse_staffing_hours_per_resident_per_day,

        -- health-inspection rating cycles
        try_cast(rating_cycle_1_standard_survey_health_date as date) as cycle_1_standard_survey_date,
        try_cast(rating_cycle_1_total_number_of_health_deficiencies as int) as cycle_1_total_health_deficiencies,
        try_cast(rating_cycle_1_number_of_standard_health_deficiencies as int) as cycle_1_standard_health_deficiencies,
        try_cast(rating_cycle_1_number_of_complaint_health_deficiencies as int) as cycle_1_complaint_health_deficiencies,
        try_cast(rating_cycle_1_health_deficiency_score as int) as cycle_1_health_deficiency_score,
        try_cast(rating_cycle_1_number_of_health_revisits as int) as cycle_1_health_revisits,
        try_cast(rating_cycle_1_health_revisit_score as int) as cycle_1_health_revisit_score,
        try_cast(rating_cycle_1_total_health_score as int) as cycle_1_total_health_score,
        try_cast(rating_cycle_2_standard_health_survey_date as date) as cycle_2_standard_survey_date,
        try_cast(rating_cycle_23_total_number_of_health_deficiencies as int) as cycle_23_total_health_deficiencies,
        try_cast(rating_cycle_2_number_of_standard_health_deficiencies as int) as cycle_2_standard_health_deficiencies,
        try_cast(rating_cycle_23_number_of_complaint_health_deficiencies as int)
            as cycle_23_complaint_health_deficiencies,
        try_cast(rating_cycle_23_health_deficiency_score as int) as cycle_23_health_deficiency_score,
        try_cast(rating_cycle_23_number_of_health_revisits as int) as cycle_23_health_revisits,
        try_cast(rating_cycle_23_health_revisit_score as int) as cycle_23_health_revisit_score,
        try_cast(rating_cycle_23_total_health_score as int) as cycle_23_total_health_score,
        try_cast(total_weighted_health_survey_score as double) as total_weighted_health_survey_score,
        try_cast(number_of_citations_from_infection_control_inspections as int) as infection_control_citations,

        -- penalties (summary counts; detail rows live in
        -- stg_cms__nursing_home_penalties)
        try_cast(number_of_fines as int) as number_of_fines,
        try_cast(total_amount_of_fines_in_dollars as decimal(12, 2)) as total_fines_dollars,
        try_cast(number_of_payment_denials as int) as number_of_payment_denials,
        try_cast(total_number_of_penalties as int) as total_number_of_penalties,

        -- geocoding
        trim(location) as location_address,
        try_cast(latitude as double) as latitude,
        try_cast(longitude as double) as longitude,
        nullif(trim(geocoding_footnote), '') as geocoding_footnote,

        -- metadata
        try_cast(processing_date as date) as processing_date

    from source

)

select * from renamed
