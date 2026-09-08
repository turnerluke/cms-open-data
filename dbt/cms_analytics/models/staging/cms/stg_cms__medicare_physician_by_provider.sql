with source as (

    select * from {{ source('cms_raw', 'cms_medicare_physician_by_provider') }}

),

renamed as (

    select
        -- identifiers (one row per rendering provider NPI)
        lpad(cast(rndrng_npi as varchar), 10, '0') as npi,
        trim(rndrng_prvdr_last_org_name) as provider_last_org_name,
        nullif(trim(rndrng_prvdr_first_name), '') as provider_first_name,
        nullif(trim(rndrng_prvdr_mi), '') as provider_middle_initial,
        nullif(trim(rndrng_prvdr_crdntls), '') as provider_credentials,
        -- entity code: 'I' individual, 'O' organization
        trim(rndrng_prvdr_ent_cd) as entity_code,

        -- address
        nullif(trim(rndrng_prvdr_st1), '') as street_address_1,
        nullif(trim(rndrng_prvdr_st2), '') as street_address_2,
        nullif(trim(rndrng_prvdr_city), '') as city,
        trim(rndrng_prvdr_state_abrvtn) as state,
        trim(rndrng_prvdr_state_fips) as state_fips,
        rndrng_prvdr_zip5 as zip5,
        -- RUCA code carries meaningful decimal subcodes like 4.1
        rndrng_prvdr_ruca as ruca_code,
        nullif(trim(rndrng_prvdr_ruca_desc), '') as ruca_description,
        trim(rndrng_prvdr_cntry) as country,

        -- provider attributes
        nullif(trim(rndrng_prvdr_type), '') as provider_type,
        -- Medicare-participation indicator: 'Y' or 'N'
        trim(rndrng_prvdr_mdcr_prtcptg_ind) as medicare_participating_indicator,

        -- overall utilization and payment totals
        tot_hcpcs_cds as total_hcpcs_codes,
        tot_benes as total_beneficiaries,
        tot_srvcs as total_services,
        tot_sbmtd_chrg as total_submitted_charges,
        tot_mdcr_alowd_amt as total_medicare_allowed_amount,
        tot_mdcr_pymt_amt as total_medicare_payment_amount,
        tot_mdcr_stdzd_amt as total_medicare_standardized_amount,

        -- drug (Part B drug administrations) totals; the suppression
        -- indicator is three-valued — '*' means the counts were below
        -- CMS's disclosure threshold, '#' means counter-suppressed so
        -- the value can't be recalculated from the totals, null means
        -- disclosed
        nullif(trim(drug_sprsn_ind), '') as drug_suppression_indicator,
        drug_tot_hcpcs_cds as drug_total_hcpcs_codes,
        drug_tot_benes as drug_total_beneficiaries,
        drug_tot_srvcs as drug_total_services,
        drug_sbmtd_chrg as drug_submitted_charges,
        drug_mdcr_alowd_amt as drug_medicare_allowed_amount,
        drug_mdcr_pymt_amt as drug_medicare_payment_amount,
        drug_mdcr_stdzd_amt as drug_medicare_standardized_amount,

        -- medical (non-drug) totals with the same suppression scheme
        nullif(trim(med_sprsn_ind), '') as medical_suppression_indicator,
        med_tot_hcpcs_cds as medical_total_hcpcs_codes,
        med_tot_benes as medical_total_beneficiaries,
        med_tot_srvcs as medical_total_services,
        med_sbmtd_chrg as medical_submitted_charges,
        med_mdcr_alowd_amt as medical_medicare_allowed_amount,
        med_mdcr_pymt_amt as medical_medicare_payment_amount,
        med_mdcr_stdzd_amt as medical_medicare_standardized_amount,

        -- beneficiary demographics
        bene_avg_age as avg_beneficiary_age,
        bene_age_lt_65_cnt as beneficiary_age_lt_65_count,
        bene_age_65_74_cnt as beneficiary_age_65_74_count,
        bene_age_75_84_cnt as beneficiary_age_75_84_count,
        bene_age_gt_84_cnt as beneficiary_age_gt_84_count,
        bene_feml_cnt as beneficiary_female_count,
        bene_male_cnt as beneficiary_male_count,
        bene_race_wht_cnt as beneficiary_race_white_count,
        bene_race_black_cnt as beneficiary_race_black_count,
        bene_race_api_cnt as beneficiary_race_asian_pacific_islander_count,
        bene_race_hspnc_cnt as beneficiary_race_hispanic_count,
        bene_race_natind_cnt as beneficiary_race_native_american_count,
        bene_race_othr_cnt as beneficiary_race_other_count,
        bene_dual_cnt as beneficiary_dual_count,
        bene_ndual_cnt as beneficiary_nondual_count,

        -- chronic-condition prevalence (percent of beneficiaries)
        bene_cc_bh_adhd_othcd_v1_pct as pct_beneficiaries_adhd_other_conduct_disorders,
        bene_cc_bh_alcohol_drug_v1_pct as pct_beneficiaries_alcohol_drug_use,
        bene_cc_bh_tobacco_v1_pct as pct_beneficiaries_tobacco_use,
        bene_cc_bh_alz_nonalzdem_v2_pct as pct_beneficiaries_alzheimers_dementia,
        bene_cc_bh_anxiety_v1_pct as pct_beneficiaries_anxiety,
        bene_cc_bh_bipolar_v1_pct as pct_beneficiaries_bipolar,
        bene_cc_bh_mood_v2_pct as pct_beneficiaries_mood_disorders,
        bene_cc_bh_depress_v1_pct as pct_beneficiaries_depression,
        bene_cc_bh_pd_v1_pct as pct_beneficiaries_personality_disorders,
        bene_cc_bh_ptsd_v1_pct as pct_beneficiaries_ptsd,
        bene_cc_bh_schizo_othpsy_v1_pct as pct_beneficiaries_schizophrenia_psychosis,
        bene_cc_ph_asthma_v2_pct as pct_beneficiaries_asthma,
        bene_cc_ph_afib_v2_pct as pct_beneficiaries_atrial_fibrillation,
        bene_cc_ph_cancer6_v2_pct as pct_beneficiaries_cancer6,
        bene_cc_ph_ckd_v2_pct as pct_beneficiaries_chronic_kidney_disease,
        bene_cc_ph_copd_v2_pct as pct_beneficiaries_copd,
        bene_cc_ph_diabetes_v2_pct as pct_beneficiaries_diabetes,
        bene_cc_ph_hf_nonihd_v2_pct as pct_beneficiaries_heart_failure_nonihd,
        bene_cc_ph_hyperlipidemia_v2_pct as pct_beneficiaries_hyperlipidemia,
        bene_cc_ph_hypertension_v2_pct as pct_beneficiaries_hypertension,
        bene_cc_ph_ischemicheart_v2_pct as pct_beneficiaries_ischemic_heart_disease,
        bene_cc_ph_osteoporosis_v2_pct as pct_beneficiaries_osteoporosis,
        bene_cc_ph_parkinson_v2_pct as pct_beneficiaries_parkinsons,
        bene_cc_ph_arthritis_v2_pct as pct_beneficiaries_arthritis,
        bene_cc_ph_stroke_tia_v2_pct as pct_beneficiaries_stroke_tia,

        -- risk
        bene_avg_risk_scre as avg_hcc_risk_score

    from source

)

select * from renamed
