with source as (

    select * from {{ source('cms_raw', 'cms_dialysis_facility_listing') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as upper(trim()) to match every
        -- other staging model that carries one. Dialysis CCNs are
        -- six digits in the current vintage (no letter-suffixed
        -- CCNs); trim/upper are cheap and future-proof against a
        -- format change. Primary key — one row per facility.
        upper(trim(cms_certification_number_ccn)) as ccn,
        trim(facility_name) as facility_name,
        -- ESRD network 1..18; kept as a string because the raw column
        -- is a text identifier, not a magnitude.
        nullif(trim(network), '') as esrd_network,

        -- address
        trim(address_line_1) as address_line_1,
        nullif(trim(address_line_2), '') as address_line_2,
        trim(citytown) as city,
        trim(state) as state,
        zip_code as zip5,
        trim(countyparish) as county,
        trim(telephone_number) as telephone_number,

        -- classification
        case
            when profit_or_nonprofit = 'Profit' then true
            when profit_or_nonprofit = 'Non-profit' then false
        end as is_for_profit,
        case
            when chain_owned = 'Yes' then true
            when chain_owned = 'No' then false
        end as is_chain_owned,
        -- Chain organization; the literal string `Independent`
        -- appears iff `chain_owned = 'No'` (verified: 742/742
        -- independents carry that value).
        trim(chain_organization) as chain_organization,
        case
            when late_shift = 'Yes' then true
            when late_shift = 'No' then false
        end as offers_late_shift,
        try_cast(of_dialysis_stations as int) as number_of_dialysis_stations,

        -- service offerings
        case
            when offers_incenter_hemodialysis = 'Yes' then true
            when offers_incenter_hemodialysis = 'No' then false
        end as offers_incenter_hemodialysis,
        case
            when offers_peritoneal_dialysis = 'Yes' then true
            when offers_peritoneal_dialysis = 'No' then false
        end as offers_peritoneal_dialysis,
        case
            when offers_home_hemodialysis_training = 'Yes' then true
            when offers_home_hemodialysis_training = 'No' then false
        end as offers_home_hemodialysis_training,

        -- certification date (CMS ships this file's dates as
        -- `YYYY-MM-DD`, so `try_cast(... as date)` handles them
        -- directly, unlike the IRF / LTCH files which use
        -- `MM/DD/YYYY`).
        try_cast(nullif(trim(certification_date), '') as date) as certification_date,

        -- measurement windows carried at file scope (all rows
        -- share a single value per column in this vintage) — kept
        -- verbatim, as with the hospice-quality measure ranges.
        nullif(trim(five_star_date), '') as five_star_period,
        nullif(trim(claims_date), '') as claims_period,
        nullif(trim(eqrs_date), '') as eqrs_period,
        nullif(trim(smr_date), '') as smr_period,
        nullif(trim(shr_date), '') as shr_period,
        nullif(trim(srr_date), '') as srr_period,
        nullif(trim(strr_date), '') as strr_period,
        nullif(trim(fyswr_date), '') as fyswr_period,
        nullif(trim(sedr_date), '') as sedr_period,
        nullif(trim(ed30_date), '') as ed30_period,
        nullif(trim(sir_date), '') as sir_period,
        nullif(trim(hcp_vaccination_data_collection_dates), '') as hcp_vaccination_period,
        nullif(trim(years_modality_switch_based_upon), '') as smosr_period,

        -- five-star overall rating (1-5; 491 rows suppressed)
        try_cast(five_star as int) as five_star,
        -- Data-availability codes across every measure in this file
        -- follow the same convention: `001` when the measure is
        -- reported and non-`001` (`199`, `201`, `256`, `258`, `260`,
        -- `280`, ...) when CMS suppresses the score for a
        -- disclosure or eligibility reason. The suppression codes
        -- are kept verbatim so consumers can distinguish "too few
        -- patients" from "not eligible to be scored".
        nullif(trim(five_star_data_availability_code), '') as five_star_data_availability_code,

        -- standardized mortality ratio (SMR)
        nullif(trim(patient_survival_category_text), '') as smr_category,
        nullif(trim(patient_survival_data_availability_code), '') as smr_data_availability_code,
        try_cast(number_of_patients_included_in_survival_summary as int)
            as smr_number_of_patients,
        try_cast(mortality_rate_facility as double) as smr_mortality_rate,
        try_cast(mortality_rate_upper_confidence_limit_975 as double)
            as smr_mortality_rate_ci_upper_975,
        try_cast(mortality_rate_lower_confidence_limit_25 as double)
            as smr_mortality_rate_ci_lower_25,

        -- standardized hospitalization ratio (SHR)
        nullif(trim(patient_hospitalization_category_text), '') as shr_category,
        nullif(trim(patient_hospitalization_data_availability_code), '') as shr_data_availability_code,
        try_cast(number_of_patients_included_in_hospitalization_summary as int)
            as shr_number_of_patients,
        try_cast(hospitalization_rate_facility as double) as shr_hospitalization_rate,
        try_cast(hospitalization_rate_upper_confidence_limit_975 as double)
            as shr_hospitalization_rate_ci_upper_975,
        try_cast(hospitalization_rate_lower_confidence_limit_25 as double)
            as shr_hospitalization_rate_ci_lower_25,

        -- standardized readmission ratio (SRR)
        nullif(trim(patient_hospital_readmission_category), '') as srr_category,
        nullif(trim(patient_hospital_readmission_data_availability_code), '') as srr_data_availability_code,
        try_cast(number_of_hospitalizations_included_in_hospital_readmission_fc2b as int)
            as srr_number_of_hospitalizations,
        try_cast(readmission_rate_facility as double) as srr_readmission_rate,
        try_cast(readmission_rate_upper_confidence_limit_975 as double)
            as srr_readmission_rate_ci_upper_975,
        try_cast(readmission_rate_lower_confidence_limit_25 as double)
            as srr_readmission_rate_ci_lower_25,

        -- standardized transfusion ratio (STrR)
        nullif(trim(patient_transfusion_category_text), '') as strr_category,
        nullif(trim(patient_transfusion_data_availability_code), '') as strr_data_availability_code,
        try_cast(number_of_patients_included_in_the_transfusion_summary as int)
            as strr_number_of_patients,
        try_cast(transfusion_rate_facility as double) as strr_transfusion_rate,
        try_cast(transfusion_rate_upper_confidence_limit_975 as double)
            as strr_transfusion_rate_ci_upper_975,
        try_cast(transfusion_rate_lower_confidence_limit_25 as double)
            as strr_transfusion_rate_ci_lower_25,

        -- first-year standardized kidney transplant waitlist ratio (FYSWR)
        nullif(trim(fyswr_category_text), '') as fyswr_category,
        nullif(trim(patient_transplant_waitlist_data_availability_code), '') as fyswr_data_availability_code,
        try_cast(number_of_patients_in_this_facility_for_fyswr as int)
            as fyswr_number_of_patients,
        try_cast(first_year_standardized_kidney_transplant_waitlist_ratio as double)
            as fyswr_ratio,
        try_cast("95_ci_upper_limit_for_fyswr" as double) as fyswr_ci_upper_95,
        try_cast("95_ci_lower_limit_for_fyswr" as double) as fyswr_ci_lower_95,

        -- percentage of prevalent patients waitlisted (PPPW)
        nullif(trim(pppw_category_text), '') as pppw_category,
        nullif(trim(patient_prevalent_transplant_waitlist_data_availability_code), '') as pppw_data_availability_code,
        try_cast(number_of_patients_for_pppw as int) as pppw_number_of_patients,
        try_cast(percentage_of_prevalent_patients_waitlisted_for_kidney_tran_ecca as double)
            as pppw_percent_waitlisted,
        try_cast("95_ci_upper_limit_for_pppw" as double) as pppw_ci_upper_95,
        try_cast("95_ci_lower_limit_for_pppw" as double) as pppw_ci_lower_95,

        -- standardized emergency-department ratio (SEDR)
        nullif(trim(sedr_category_text), '') as sedr_category,
        nullif(trim(emergency_department_encounter_data_availability_code), '') as sedr_data_availability_code,
        try_cast(number_of_patients_included_in_sedr_summary as int)
            as sedr_number_of_patients,
        try_cast(standardized_ed_visits_ratio_facility as double) as sedr_ratio,
        try_cast(sedr_upper_confidence_limit_975 as double) as sedr_ci_upper_975,
        try_cast(sedr_lower_confidence_limit_25 as double) as sedr_ci_lower_25,

        -- ED encounters within 30 days of hospital discharge (ED30)
        nullif(trim(ed30_category_text), '') as ed30_category,
        nullif(trim(emergency_department_encounter_ratio_occurring_within_30_da_f8e3), '')
            as ed30_data_availability_code,
        try_cast(number_of_hospitalizations_included_in_ed30_summary as int)
            as ed30_number_of_hospitalizations,
        try_cast(standardized_ed_visits_within_30_days_of_hospital_discharge_6307 as double)
            as ed30_ratio,
        try_cast(ed30_upper_confidence_limit_975 as double) as ed30_ci_upper_975,
        try_cast(ed30_lower_confidence_limit_25 as double) as ed30_ci_lower_25,

        -- standardized modality-switch ratio (SMOSR)
        nullif(trim(smosr_classification_category_facility), '') as smosr_category,
        nullif(trim(modality_switch_data_availability_code), '') as smosr_data_availability_code,
        try_cast(smosr_number_of_eligible_patients_facility as int)
            as smosr_number_of_patients,
        try_cast(smosr_standardized_modality_switch_ratio_facility as double)
            as smosr_ratio,
        try_cast(smosr_upper_confidence_limit_facility as double) as smosr_ci_upper,
        try_cast(smosr_lower_confidence_limit_facility as double) as smosr_ci_lower,

        -- standardized infection ratio (SIR)
        nullif(trim(patient_infection_category_text), '') as sir_category,
        nullif(trim(patient_infection_data_availability_code), '') as sir_data_availability_code,
        try_cast(standard_infection_ratio as double) as sir_ratio,
        try_cast(sir_upper_confidence_limit_975 as double) as sir_ci_upper_975,
        try_cast(sir_lower_confidence_limit_25 as double) as sir_ci_lower_25,

        -- arteriovenous-fistula use
        nullif(trim(fistula_category_text), '') as fistula_category,
        nullif(trim(fistula_data_availability_code), '') as fistula_data_availability_code,
        try_cast(number_of_patients_included_in_fistula_summary as int)
            as fistula_number_of_patients,
        try_cast(fistula_rate_facility as double) as fistula_rate,
        try_cast(fistula_rate_upper_confidence_limit_975 as double)
            as fistula_rate_ci_upper_975,
        try_cast(fistula_rate_lower_confidence_limit_25 as double)
            as fistula_rate_ci_lower_25,

        -- health-care personnel COVID-19 vaccination adherence
        nullif(trim(hcp_vaccination_data_availability_code), '') as hcp_vaccination_data_availability_code,
        try_cast(healthcare_worker_covid19_vaccination_adherence_percentage as double)
            as hcp_vaccination_percent,

        -- dialysis adequacy (Kt/V) percentages — reported four ways
        -- (adult / pediatric x hemodialysis / peritoneal dialysis)
        nullif(trim(adult_hd_ktv_data_availability_code), '') as adult_hd_ktv_data_availability_code,
        try_cast(number_of_adult_hd_patients_with_ktv_data as int)
            as adult_hd_ktv_number_of_patients,
        try_cast(number_of_adult_hd_patientmonths_with_ktv_data as int)
            as adult_hd_ktv_number_of_patient_months,
        try_cast(percent_of_adult_hd_patients_with_ktv__12 as double)
            as adult_hd_ktv_percent_at_or_above_12,
        nullif(trim(adult_pd_ktv_data_availability_code), '') as adult_pd_ktv_data_availability_code,
        try_cast(number_of_adult_pd_patients_with_ktv_data as int)
            as adult_pd_ktv_number_of_patients,
        try_cast(number_of_adult_pd_patientmonths_with_ktv_data as int)
            as adult_pd_ktv_number_of_patient_months,
        try_cast(percentage_of_adult_pd_pts_with_ktv__17 as double)
            as adult_pd_ktv_percent_at_or_above_17,
        nullif(trim(pediatric_hd_ktv_data_availability_code), '') as pediatric_hd_ktv_data_availability_code,
        try_cast(number_of_pediatric_hd_patients_with_ktv_data as int)
            as pediatric_hd_ktv_number_of_patients,
        try_cast(number_of_pediatric_hd_patientmonths_with_ktv_data as int)
            as pediatric_hd_ktv_number_of_patient_months,
        try_cast(percentage_of_pediatric_hd_patients_with_ktv__12 as double)
            as pediatric_hd_ktv_percent_at_or_above_12,
        nullif(trim(pediatric_pd_ktv_data_availability_code), '') as pediatric_pd_ktv_data_availability_code,
        try_cast(number_of_pediatric_pd_patients_with_ktv_data as int)
            as pediatric_pd_ktv_number_of_patients,
        try_cast(number_of_pediatric_pd_patientmonths_with_ktv_data as int)
            as pediatric_pd_ktv_number_of_patient_months,
        try_cast(percentage_of_pediatric_pd_patients_with_ktv18 as double)
            as pediatric_pd_ktv_percent_at_or_above_18,

        -- hemoglobin management (paired thresholds 10 g/dL and 12 g/dL)
        nullif(trim(hgb10_data_availability_code), '') as hgb_lt_10_data_availability_code,
        try_cast(percentage_of_medicare_patients_with_hgb10_gdl as double)
            as hgb_lt_10_percent,
        nullif(trim(hgb__12_data_availability_code), '') as hgb_gt_12_data_availability_code,
        try_cast(percentage_of_medicare_patients_with_hgb12_gdl as double)
            as hgb_gt_12_percent,
        try_cast(number_of_dialysis_patients_with_hgb_data as int)
            as hgb_number_of_patients,

        -- mineral-metabolism measures
        nullif(trim(hypercalcemia_data_availability_code), '') as hypercalcemia_data_availability_code,
        try_cast(number_of_patients_in_hypercalcemia_summary as int)
            as hypercalcemia_number_of_patients,
        try_cast(number_of_patientmonths_in_hypercalcemia_summary as int)
            as hypercalcemia_number_of_patient_months,
        try_cast(percentage_of_adult_patients_with_hypercalcemia_serum_calci_044d as double)
            as hypercalcemia_percent,

        -- serum phosphorus band percentages (five bands share one
        -- availability code / denominator)
        nullif(trim(serum_phosphorus_data_availability_code), '') as serum_phosphorus_data_availability_code,
        try_cast(number_of_patients_in_serum_phosphorus_summary as int)
            as serum_phosphorus_number_of_patients,
        try_cast(number_of_patientmonths_in_serum_phosphorus_summary as int)
            as serum_phosphorus_number_of_patient_months,
        try_cast(percentage_of_adult_patients_with_serum_phosphorus_less_tha_c222 as double)
            as serum_phosphorus_percent_lt_3_5,
        try_cast(percentage_of_adult_patients_with_serum_phosphorus_between__85e8 as double)
            as serum_phosphorus_percent_3_5_to_4_5,
        try_cast(percentage_of_adult_patients_with_serum_phosphorus_between__fad7 as double)
            as serum_phosphorus_percent_4_6_to_5_5,
        try_cast(percentage_of_adult_patients_with_serum_phosphorus_between__ff32 as double)
            as serum_phosphorus_percent_5_6_to_7_0,
        try_cast(percentage_of_adult_patients_with_serum_phosphorus_greater__d8e3 as double)
            as serum_phosphorus_percent_gt_7_0,

        -- long-term catheter use
        nullif(trim(long_term_catheter_data_availability_code), '') as long_term_catheter_data_availability_code,
        try_cast(number_of_patients_in_long_term_catheter_summary as int)
            as long_term_catheter_number_of_patients,
        try_cast(number_of_patient_months_in_long_term_catheter_summary as int)
            as long_term_catheter_number_of_patient_months,
        try_cast(percentage_of_adult_patients_with_long_term_catheter_in_use as double)
            as long_term_catheter_percent,

        -- normalized protein catabolic rate (pediatric HD only)
        nullif(trim(npcr_data_availability_code), '') as npcr_data_availability_code,
        try_cast(number_of_patients_in_npcr_summary as int) as npcr_number_of_patients,
        try_cast(number_of_patientmonths_in_npcr_summary as int) as npcr_number_of_patient_months,
        try_cast(percentage_of_pediatric_hd_patients_with_npcr as double)
            as npcr_pediatric_hd_percent

    from source

)

select * from renamed
