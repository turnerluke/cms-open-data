with source as (

    select * from {{ source('cms_raw', 'cms_home_health_care_agencies') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as upper(trim()) to match the
        -- convention used across every other staging model that
        -- carries a CCN. Home-health agency CCNs are six characters
        -- (numeric, or with a letter in the third position, e.g.
        -- `017001`, `07A001`) and share the CCN namespace with no
        -- other provider type in this file.
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(provider_name) as provider_name,

        -- address
        trim(address) as address,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        trim(telephone_number) as telephone_number,

        -- classification
        trim(type_of_ownership) as ownership_type,
        try_cast(certification_date as date) as certification_date,

        -- offered services ('Yes'/'No' → boolean; any other value
        -- including the '-' sentinel and empty string → NULL by design)
        case
            when offers_nursing_care_services = 'Yes' then true
            when offers_nursing_care_services = 'No' then false
        end as offers_nursing_care,
        case
            when offers_physical_therapy_services = 'Yes' then true
            when offers_physical_therapy_services = 'No' then false
        end as offers_physical_therapy,
        case
            when offers_occupational_therapy_services = 'Yes' then true
            when offers_occupational_therapy_services = 'No' then false
        end as offers_occupational_therapy,
        case
            when offers_speech_pathology_services = 'Yes' then true
            when offers_speech_pathology_services = 'No' then false
        end as offers_speech_pathology,
        case
            when offers_medical_social_services = 'Yes' then true
            when offers_medical_social_services = 'No' then false
        end as offers_medical_social_services,
        case
            when offers_home_health_aide_services = 'Yes' then true
            when offers_home_health_aide_services = 'No' then false
        end as offers_home_health_aide,

        -- overall star rating (1-5 in half-star increments; empty
        -- string / 'Not Available' becomes null)
        try_cast(quality_of_patient_care_star_rating as double) as quality_of_patient_care_star_rating,
        nullif(trim(footnote_for_quality_of_patient_care_star_rating), '') as quality_of_patient_care_star_rating_footnote,

        -- ~40 wide OASIS / claims-based quality measures. Kept as text
        -- + typed pairs here because CMS ships numerators, denominators
        -- and rates side-by-side as strings; a later PR unpivots them
        -- into a long-format fact.

        -- OASIS process/outcome measures (percentages, 0-100)
        try_cast(numerator_for_how_often_the_home_health_team_began_their_pa_ada1 as int)
            as timely_initiation_numerator,
        try_cast(denominator_for_how_often_the_home_health_team_began_their__9354 as int)
            as timely_initiation_denominator,
        try_cast(how_often_the_home_health_team_began_their_patients_care_in_d440 as double)
            as timely_initiation_rate,
        nullif(trim(footnote_for_how_often_the_home_health_team_began_their_pat_6aee), '')
            as timely_initiation_footnote,

        try_cast(numerator_for_how_often_the_home_health_team_determined_whe_72da as int)
            as drug_education_numerator,
        try_cast(denominator_for_how_often_the_home_health_team_determined_w_81bc as int)
            as drug_education_denominator,
        try_cast(how_often_the_home_health_team_determined_whether_patients__4505 as double)
            as drug_education_rate,
        nullif(trim(footnote_for_how_often_the_home_health_team_determined_whet_5002), '')
            as drug_education_footnote,

        try_cast(numerator_for_how_often_patients_got_better_at_walking_or_m_3b64 as int)
            as improve_ambulation_numerator,
        try_cast(denominator_for_how_often_patients_got_better_at_walking_or_b3eb as int)
            as improve_ambulation_denominator,
        try_cast(how_often_patients_got_better_at_walking_or_moving_around as double)
            as improve_ambulation_rate,
        nullif(trim(footnote_for_how_often_patients_got_better_at_walking_or_mo_e2ff), '')
            as improve_ambulation_footnote,

        try_cast(numerator_for_how_often_patients_got_better_at_getting_in_a_e863 as int)
            as improve_bed_transferring_numerator,
        try_cast(denominator_for_how_often_patients_got_better_at_getting_in_4b7a as int)
            as improve_bed_transferring_denominator,
        try_cast(how_often_patients_got_better_at_getting_in_and_out_of_bed as double)
            as improve_bed_transferring_rate,
        nullif(trim(footnote_for_how_often_patients_got_better_at_getting_in_an_7940), '')
            as improve_bed_transferring_footnote,

        try_cast(numerator_for_how_often_patients_got_better_at_bathing as int)
            as improve_bathing_numerator,
        try_cast(denominator_for_how_often_patients_got_better_at_bathing as int)
            as improve_bathing_denominator,
        try_cast(how_often_patients_got_better_at_bathing as double) as improve_bathing_rate,
        nullif(trim(footnote_for_how_often_patients_got_better_at_bathing), '')
            as improve_bathing_footnote,

        try_cast(numerator_for_how_often_patients_breathing_improved as int)
            as improve_breathing_numerator,
        try_cast(denominator_for_how_often_patients_breathing_improved as int)
            as improve_breathing_denominator,
        try_cast(how_often_patients_breathing_improved as double) as improve_breathing_rate,
        nullif(trim(footnote_for_how_often_patients_breathing_improved), '')
            as improve_breathing_footnote,

        try_cast(numerator_for_how_often_patients_got_better_at_taking_their_2828 as int)
            as improve_drug_taking_numerator,
        try_cast(denominator_for_how_often_patients_got_better_at_taking_the_0424 as int)
            as improve_drug_taking_denominator,
        try_cast(how_often_patients_got_better_at_taking_their_drugs_correct_bd88 as double)
            as improve_drug_taking_rate,
        nullif(trim(footnote_for_how_often_patients_got_better_at_taking_their__dd00), '')
            as improve_drug_taking_footnote,

        try_cast(numerator_for_changes_in_skin_integrity_postacute_care_pres_bea9 as int)
            as pressure_ulcer_numerator,
        try_cast(denominator_for_changes_in_skin_integrity_postacute_care_pr_7aaf as int)
            as pressure_ulcer_denominator,
        try_cast(changes_in_skin_integrity_postacute_care_pressure_ulcerinjury as double)
            as pressure_ulcer_rate,
        nullif(trim(footnote_changes_in_skin_integrity_postacute_care_pressure__d758), '')
            as pressure_ulcer_footnote,

        try_cast(numerator_for_how_often_physicianrecommended_actions_to_add_ab2a as int)
            as medication_action_numerator,
        try_cast(denominator_for_how_often_physicianrecommended_actions_to_a_67ae as int)
            as medication_action_denominator,
        try_cast(how_often_physicianrecommended_actions_to_address_medicatio_cc88 as double)
            as medication_action_rate,
        nullif(trim(footnote_for_how_often_physicianrecommended_actions_to_addr_0c32), '')
            as medication_action_footnote,

        try_cast(numerator_for_percent_of_residents_experiencing_one_or_more_cca9 as int)
            as major_falls_numerator,
        try_cast(denominator_for_percent_of_residents_experiencing_one_or_mo_e12a as int)
            as major_falls_denominator,
        try_cast(percent_of_residents_experiencing_one_or_more_falls_with_ma_34b8 as double)
            as major_falls_rate,
        nullif(trim(footnote_for_percent_of_residents_experiencing_one_or_more__4fe2), '')
            as major_falls_footnote,

        try_cast(numerator_for_discharge_function_score as int) as discharge_function_numerator,
        try_cast(denominator_for_discharge_function_score as int) as discharge_function_denominator,
        try_cast(discharge_function_score as double) as discharge_function_rate,
        nullif(trim(footnote_for_discharge_function_score), '') as discharge_function_footnote,

        try_cast(numerator_for_transfer_of_health_information_to_the_provider as int)
            as transfer_hi_provider_numerator,
        try_cast(denominator_for_transfer_of_health_information_to_the_provider as int)
            as transfer_hi_provider_denominator,
        try_cast(transfer_of_health_information_to_the_provider as double)
            as transfer_hi_provider_rate,
        nullif(trim(footnote_for_transfer_of_health_information_to_the_provider), '')
            as transfer_hi_provider_footnote,

        try_cast(numerator_for_transfer_of_health_information_to_the_patient as int)
            as transfer_hi_patient_numerator,
        try_cast(denominator_for_transfer_of_health_information_to_the_patient as int)
            as transfer_hi_patient_denominator,
        try_cast(transfer_of_health_information_to_the_patient as double)
            as transfer_hi_patient_rate,
        nullif(trim(footnote_for_transfer_of_health_information_to_the_patient), '')
            as transfer_hi_patient_footnote,

        -- claims-based measures (DTC = discharge to community,
        -- PPR = potentially preventable readmissions,
        -- PPH = potentially preventable hospitalizations); risk-
        -- standardized rates with confidence bounds and a categorical
        -- performance bucket
        try_cast(dtc_numerator as int) as dtc_numerator,
        try_cast(dtc_denominator as int) as dtc_denominator,
        try_cast(dtc_observed_rate as double) as dtc_observed_rate,
        try_cast(dtc_riskstandardized_rate as double) as dtc_risk_standardized_rate,
        try_cast(dtc_riskstandardized_rate_lower_limit as double) as dtc_risk_standardized_rate_lower,
        try_cast(dtc_riskstandardized_rate_upper_limit as double) as dtc_risk_standardized_rate_upper,
        -- CMS uses '-' as a not-applicable sentinel here (~3k rows
        -- per column) alongside the empty-string sentinel; strip both
        nullif(nullif(trim(dtc_performance_categorization), ''), '-') as dtc_performance_category,
        nullif(trim(footnote_for_dtc_riskstandardized_rate), '') as dtc_footnote,

        try_cast(ppr_numerator as int) as ppr_numerator,
        try_cast(ppr_denominator as int) as ppr_denominator,
        try_cast(ppr_observed_rate as double) as ppr_observed_rate,
        try_cast(ppr_riskstandardized_rate as double) as ppr_risk_standardized_rate,
        try_cast(ppr_riskstandardized_rate_lower_limit as double) as ppr_risk_standardized_rate_lower,
        try_cast(ppr_riskstandardized_rate_upper_limit as double) as ppr_risk_standardized_rate_upper,
        nullif(nullif(trim(ppr_performance_categorization), ''), '-') as ppr_performance_category,
        nullif(trim(footnote_for_ppr_riskstandardized_rate), '') as ppr_footnote,

        try_cast(pph_numerator as int) as pph_numerator,
        try_cast(pph_denominator as int) as pph_denominator,
        try_cast(pph_observed_rate as double) as pph_observed_rate,
        try_cast(pph_riskstandardized_rate as double) as pph_risk_standardized_rate,
        try_cast(pph_riskstandardized_rate_lower_limit as double) as pph_risk_standardized_rate_lower,
        try_cast(pph_riskstandardized_rate_upper_limit as double) as pph_risk_standardized_rate_upper,
        nullif(nullif(trim(pph_performance_categorization), ''), '-') as pph_performance_category,
        nullif(trim(footnote_for_pph_riskstandardized_rate), '') as pph_footnote,

        -- Medicare spending per episode
        try_cast(how_much_medicare_spends_on_an_episode_of_care_at_this_agen_56e6 as double)
            as medicare_spending_per_episode,
        nullif(trim(footnote_for_how_much_medicare_spends_on_an_episode_of_care_5dfd), '')
            as medicare_spending_per_episode_footnote,
        try_cast(no_of_episodes_to_calc_how_much_medicare_spends_per_episode_4f4e as int)
            as episodes_for_medicare_spending

    from source

)

select * from renamed
