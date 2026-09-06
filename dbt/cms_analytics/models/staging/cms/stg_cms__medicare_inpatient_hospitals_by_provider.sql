with source as (

    select * from {{ source('cms_raw', 'cms_medicare_inpatient_hospitals_by_provider') }}

),

renamed as (

    select
        -- identifiers (one row per hospital CCN)
        -- CCN join key, conformed as in
        -- stg_cms__hospital_general_information
        upper(trim(rndrng_prvdr_ccn)) as ccn,
        trim(rndrng_prvdr_org_name) as provider_name,

        -- address
        nullif(trim(rndrng_prvdr_st), '') as street_address,
        nullif(trim(rndrng_prvdr_city), '') as city,
        trim(rndrng_prvdr_state_abrvtn) as state,
        trim(rndrng_prvdr_state_fips) as state_fips,
        rndrng_prvdr_zip5 as zip5,
        rndrng_prvdr_ruca as ruca_code,
        nullif(trim(rndrng_prvdr_ruca_desc), '') as ruca_description,

        -- utilization totals
        tot_benes as total_beneficiaries,
        tot_dschrgs as total_discharges,
        tot_cvrd_days as total_covered_days,
        tot_days as total_days,

        -- payment totals
        tot_submtd_cvrd_chrg as total_submitted_covered_charges,
        tot_pymt_amt as total_payment_amount,
        tot_mdcr_pymt_amt as total_medicare_payment_amount,

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
