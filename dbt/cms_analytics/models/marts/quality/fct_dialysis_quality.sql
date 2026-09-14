-- Dialysis facility quality measures in long format. The source ships
-- each measure in its own set of wide columns (score, availability
-- code, patient count/patient-months, CI bounds), and every measure
-- follows the same suppression convention: availability code `001`
-- means reported, non-`001` means CMS-suppressed and the numeric
-- score is NULL. The wide source is pivoted here so downstream
-- consumers can iterate measures without hard-coding column names.
--
-- Denominator semantics vary by measure family:
--   * SMR / SHR / STrR / FYSWR / PPPW / SEDR / fistula / long-term
--     catheter / NPCR: patients
--   * SRR / ED30: hospitalizations
--   * Adult HD / Adult PD / Pediatric HD / Pediatric PD Kt/V and
--     hypercalcemia / serum phosphorus / long-term catheter / NPCR:
--     patient-months (a paired `_number_of_patients` also exists
--     upstream; the mart carries patient-months because that is the
--     denominator CMS uses for the reported percentage)
--   * SIR / hemoglobin / HCP vaccination / five-star: no per-row
--     denominator ships in the source
-- `denominator_unit` records the unit so aggregations stay honest.

with source as (

    select
        ccn,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'dialysis_facility_listing'
        ) as as_of,
        *
    from {{ ref('stg_cms__dialysis_facility_listing') }}

),

five_star as (
    select
        ccn,
        'five_star' as measure_code,
        'Overall five-star rating' as measure_name,
        cast(null as varchar) as category,
        five_star_data_availability_code as availability_code,
        try_cast(five_star as double) as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        cast(null as int) as denominator,
        cast(null as varchar) as denominator_unit,
        five_star_period as period_text,
        as_of
    from source
),

smr as (
    select
        ccn,
        'smr' as measure_code,
        'Standardized mortality ratio' as measure_name,
        smr_category as category,
        smr_data_availability_code as availability_code,
        smr_mortality_rate as score_numeric,
        smr_mortality_rate_ci_upper_975 as ci_upper,
        smr_mortality_rate_ci_lower_25 as ci_lower,
        smr_number_of_patients as denominator,
        'patients' as denominator_unit,
        smr_period as period_text,
        as_of
    from source
),

shr as (
    select
        ccn,
        'shr' as measure_code,
        'Standardized hospitalization ratio' as measure_name,
        shr_category as category,
        shr_data_availability_code as availability_code,
        shr_hospitalization_rate as score_numeric,
        shr_hospitalization_rate_ci_upper_975 as ci_upper,
        shr_hospitalization_rate_ci_lower_25 as ci_lower,
        shr_number_of_patients as denominator,
        'patients' as denominator_unit,
        shr_period as period_text,
        as_of
    from source
),

srr as (
    select
        ccn,
        'srr' as measure_code,
        'Standardized readmission ratio' as measure_name,
        srr_category as category,
        srr_data_availability_code as availability_code,
        srr_readmission_rate as score_numeric,
        srr_readmission_rate_ci_upper_975 as ci_upper,
        srr_readmission_rate_ci_lower_25 as ci_lower,
        srr_number_of_hospitalizations as denominator,
        'hospitalizations' as denominator_unit,
        srr_period as period_text,
        as_of
    from source
),

strr as (
    select
        ccn,
        'strr' as measure_code,
        'Standardized transfusion ratio' as measure_name,
        strr_category as category,
        strr_data_availability_code as availability_code,
        strr_transfusion_rate as score_numeric,
        strr_transfusion_rate_ci_upper_975 as ci_upper,
        strr_transfusion_rate_ci_lower_25 as ci_lower,
        strr_number_of_patients as denominator,
        'patients' as denominator_unit,
        strr_period as period_text,
        as_of
    from source
),

fyswr as (
    select
        ccn,
        'fyswr' as measure_code,
        'First-year standardized kidney transplant waitlist ratio' as measure_name,
        fyswr_category as category,
        fyswr_data_availability_code as availability_code,
        fyswr_ratio as score_numeric,
        fyswr_ci_upper_95 as ci_upper,
        fyswr_ci_lower_95 as ci_lower,
        fyswr_number_of_patients as denominator,
        'patients' as denominator_unit,
        fyswr_period as period_text,
        as_of
    from source
),

pppw as (
    select
        ccn,
        'pppw' as measure_code,
        'Percentage of prevalent patients waitlisted for transplant' as measure_name,
        pppw_category as category,
        pppw_data_availability_code as availability_code,
        pppw_percent_waitlisted as score_numeric,
        pppw_ci_upper_95 as ci_upper,
        pppw_ci_lower_95 as ci_lower,
        pppw_number_of_patients as denominator,
        'patients' as denominator_unit,
        -- PPPW shares FYSWR's measurement window
        fyswr_period as period_text,
        as_of
    from source
),

sedr as (
    select
        ccn,
        'sedr' as measure_code,
        'Standardized emergency-department ratio' as measure_name,
        sedr_category as category,
        sedr_data_availability_code as availability_code,
        sedr_ratio as score_numeric,
        sedr_ci_upper_975 as ci_upper,
        sedr_ci_lower_25 as ci_lower,
        sedr_number_of_patients as denominator,
        'patients' as denominator_unit,
        sedr_period as period_text,
        as_of
    from source
),

ed30 as (
    select
        ccn,
        'ed30' as measure_code,
        'ED encounters within 30 days of hospital discharge' as measure_name,
        ed30_category as category,
        ed30_data_availability_code as availability_code,
        ed30_ratio as score_numeric,
        ed30_ci_upper_975 as ci_upper,
        ed30_ci_lower_25 as ci_lower,
        ed30_number_of_hospitalizations as denominator,
        'hospitalizations' as denominator_unit,
        ed30_period as period_text,
        as_of
    from source
),

smosr as (
    select
        ccn,
        'smosr' as measure_code,
        'Standardized modality-switch ratio' as measure_name,
        smosr_category as category,
        smosr_data_availability_code as availability_code,
        smosr_ratio as score_numeric,
        smosr_ci_upper as ci_upper,
        smosr_ci_lower as ci_lower,
        smosr_number_of_patients as denominator,
        'patients' as denominator_unit,
        smosr_period as period_text,
        as_of
    from source
),

sir as (
    select
        ccn,
        'sir' as measure_code,
        'Standardized infection ratio' as measure_name,
        sir_category as category,
        sir_data_availability_code as availability_code,
        sir_ratio as score_numeric,
        sir_ci_upper_975 as ci_upper,
        sir_ci_lower_25 as ci_lower,
        cast(null as int) as denominator,
        cast(null as varchar) as denominator_unit,
        sir_period as period_text,
        as_of
    from source
),

fistula as (
    select
        ccn,
        'fistula' as measure_code,
        'Arteriovenous-fistula use' as measure_name,
        fistula_category as category,
        fistula_data_availability_code as availability_code,
        fistula_rate as score_numeric,
        fistula_rate_ci_upper_975 as ci_upper,
        fistula_rate_ci_lower_25 as ci_lower,
        fistula_number_of_patients as denominator,
        'patients' as denominator_unit,
        claims_period as period_text,
        as_of
    from source
),

hcp_vaccination as (
    select
        ccn,
        'hcp_vaccination' as measure_code,
        'Healthcare-worker COVID-19 vaccination adherence' as measure_name,
        cast(null as varchar) as category,
        hcp_vaccination_data_availability_code as availability_code,
        hcp_vaccination_percent as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        cast(null as int) as denominator,
        cast(null as varchar) as denominator_unit,
        hcp_vaccination_period as period_text,
        as_of
    from source
),

adult_hd_ktv as (
    select
        ccn,
        'adult_hd_ktv' as measure_code,
        'Adult hemodialysis Kt/V >= 1.2 (percent of patients)' as measure_name,
        cast(null as varchar) as category,
        adult_hd_ktv_data_availability_code as availability_code,
        adult_hd_ktv_percent_at_or_above_12 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        adult_hd_ktv_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

adult_pd_ktv as (
    select
        ccn,
        'adult_pd_ktv' as measure_code,
        'Adult peritoneal dialysis Kt/V >= 1.7 (percent of patients)' as measure_name,
        cast(null as varchar) as category,
        adult_pd_ktv_data_availability_code as availability_code,
        adult_pd_ktv_percent_at_or_above_17 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        adult_pd_ktv_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

pediatric_hd_ktv as (
    select
        ccn,
        'pediatric_hd_ktv' as measure_code,
        'Pediatric hemodialysis Kt/V >= 1.2 (percent of patients)' as measure_name,
        cast(null as varchar) as category,
        pediatric_hd_ktv_data_availability_code as availability_code,
        pediatric_hd_ktv_percent_at_or_above_12 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        pediatric_hd_ktv_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

pediatric_pd_ktv as (
    select
        ccn,
        'pediatric_pd_ktv' as measure_code,
        'Pediatric peritoneal dialysis Kt/V >= 1.8 (percent of patients)' as measure_name,
        cast(null as varchar) as category,
        pediatric_pd_ktv_data_availability_code as availability_code,
        pediatric_pd_ktv_percent_at_or_above_18 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        pediatric_pd_ktv_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

hgb_lt_10 as (
    select
        ccn,
        'hgb_lt_10' as measure_code,
        'Percent of Medicare patients with hemoglobin < 10 g/dL' as measure_name,
        cast(null as varchar) as category,
        hgb_lt_10_data_availability_code as availability_code,
        hgb_lt_10_percent as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        hgb_number_of_patients as denominator,
        'patients' as denominator_unit,
        claims_period as period_text,
        as_of
    from source
),

hgb_gt_12 as (
    select
        ccn,
        'hgb_gt_12' as measure_code,
        'Percent of Medicare patients with hemoglobin > 12 g/dL' as measure_name,
        cast(null as varchar) as category,
        hgb_gt_12_data_availability_code as availability_code,
        hgb_gt_12_percent as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        hgb_number_of_patients as denominator,
        'patients' as denominator_unit,
        claims_period as period_text,
        as_of
    from source
),

hypercalcemia as (
    select
        ccn,
        'hypercalcemia' as measure_code,
        'Percent of adult patients with hypercalcemia' as measure_name,
        cast(null as varchar) as category,
        hypercalcemia_data_availability_code as availability_code,
        hypercalcemia_percent as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        hypercalcemia_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

-- Serum phosphorus ships as five bands sharing one availability code
-- and denominator; each band becomes its own measure_code so score
-- semantics stay unambiguous.
serum_phosphorus_lt_35 as (
    select
        ccn,
        'serum_phosphorus_lt_3_5' as measure_code,
        'Percent of adult patients with serum phosphorus < 3.5 mg/dL' as measure_name,
        cast(null as varchar) as category,
        serum_phosphorus_data_availability_code as availability_code,
        serum_phosphorus_percent_lt_3_5 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        serum_phosphorus_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

serum_phosphorus_35_45 as (
    select
        ccn,
        'serum_phosphorus_3_5_to_4_5' as measure_code,
        'Percent of adult patients with serum phosphorus 3.5-4.5 mg/dL' as measure_name,
        cast(null as varchar) as category,
        serum_phosphorus_data_availability_code as availability_code,
        serum_phosphorus_percent_3_5_to_4_5 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        serum_phosphorus_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

serum_phosphorus_46_55 as (
    select
        ccn,
        'serum_phosphorus_4_6_to_5_5' as measure_code,
        'Percent of adult patients with serum phosphorus 4.6-5.5 mg/dL' as measure_name,
        cast(null as varchar) as category,
        serum_phosphorus_data_availability_code as availability_code,
        serum_phosphorus_percent_4_6_to_5_5 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        serum_phosphorus_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

serum_phosphorus_56_70 as (
    select
        ccn,
        'serum_phosphorus_5_6_to_7_0' as measure_code,
        'Percent of adult patients with serum phosphorus 5.6-7.0 mg/dL' as measure_name,
        cast(null as varchar) as category,
        serum_phosphorus_data_availability_code as availability_code,
        serum_phosphorus_percent_5_6_to_7_0 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        serum_phosphorus_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

serum_phosphorus_gt_70 as (
    select
        ccn,
        'serum_phosphorus_gt_7_0' as measure_code,
        'Percent of adult patients with serum phosphorus > 7.0 mg/dL' as measure_name,
        cast(null as varchar) as category,
        serum_phosphorus_data_availability_code as availability_code,
        serum_phosphorus_percent_gt_7_0 as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        serum_phosphorus_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

long_term_catheter as (
    select
        ccn,
        'long_term_catheter' as measure_code,
        'Percent of adult patients with long-term catheter in use' as measure_name,
        cast(null as varchar) as category,
        long_term_catheter_data_availability_code as availability_code,
        long_term_catheter_percent as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        long_term_catheter_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        claims_period as period_text,
        as_of
    from source
),

npcr as (
    select
        ccn,
        'npcr' as measure_code,
        'Pediatric hemodialysis normalized protein catabolic rate' as measure_name,
        cast(null as varchar) as category,
        npcr_data_availability_code as availability_code,
        npcr_pediatric_hd_percent as score_numeric,
        cast(null as double) as ci_upper,
        cast(null as double) as ci_lower,
        npcr_number_of_patient_months as denominator,
        'patient_months' as denominator_unit,
        eqrs_period as period_text,
        as_of
    from source
),

unioned as (
    select * from five_star
    union all
    select * from smr
    union all
    select * from shr
    union all
    select * from srr
    union all
    select * from strr
    union all
    select * from fyswr
    union all
    select * from pppw
    union all
    select * from sedr
    union all
    select * from ed30
    union all
    select * from smosr
    union all
    select * from sir
    union all
    select * from fistula
    union all
    select * from hcp_vaccination
    union all
    select * from adult_hd_ktv
    union all
    select * from adult_pd_ktv
    union all
    select * from pediatric_hd_ktv
    union all
    select * from pediatric_pd_ktv
    union all
    select * from hgb_lt_10
    union all
    select * from hgb_gt_12
    union all
    select * from hypercalcemia
    union all
    select * from serum_phosphorus_lt_35
    union all
    select * from serum_phosphorus_35_45
    union all
    select * from serum_phosphorus_46_55
    union all
    select * from serum_phosphorus_56_70
    union all
    select * from serum_phosphorus_gt_70
    union all
    select * from long_term_catheter
    union all
    select * from npcr
),

-- Parse the CMS-specific `%d%b%Y-%d%b%Y` measurement window (e.g.
-- `01Jan2021-31Dec2024`) into dates. `try_strptime` returns NULL on
-- any malformed value rather than raising, which future-proofs the
-- fact against a format change. All 13 distinct window strings across
-- the current vintage are well-formed.
final as (
    select
        ccn,
        measure_code,
        measure_name,
        category,
        availability_code,
        -- True iff CMS reported a real value for this measure at this
        -- facility. Non-`001` availability codes correspond to CMS
        -- suppression reasons (too few patients, not eligible, etc.).
        availability_code = '001' as is_reported,
        score_numeric,
        ci_upper,
        ci_lower,
        denominator,
        denominator_unit,
        period_text,
        cast(try_strptime(split_part(period_text, '-', 1), '%d%b%Y') as date)
            as period_start_date,
        cast(try_strptime(split_part(period_text, '-', 2), '%d%b%Y') as date)
            as period_end_date,
        as_of
    from unioned
)

select * from final
