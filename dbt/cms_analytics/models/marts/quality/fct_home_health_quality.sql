with agency as (

    select * from {{ ref('stg_cms__home_health_care_agencies') }}

),

national as (

    select * from {{ ref('stg_cms__home_health_national') }}

),

vintage as (

    -- both source files come from the same Care Compare snapshot;
    -- a future desync would need to surface as distinct `as_of`
    -- values per branch rather than being silently collapsed
    select vintages.modified as as_of
    from {{ ref('stg_cms__dataset_vintages') }} as vintages
    where vintages.dataset_key = 'home_health_care_agencies'

),

-- Base CTE joining every agency to the one-row national benchmark
-- and the snapshot vintage. All measure branches below select from
-- this so each row already carries its own national value and
-- as_of without redoing the cross join per branch.
base as (

    select
        agency.*,
        national.timely_initiation_rate as national_timely_initiation_rate,
        national.drug_education_rate as national_drug_education_rate,
        national.improve_ambulation_rate as national_improve_ambulation_rate,
        national.improve_bed_transferring_rate as national_improve_bed_transferring_rate,
        national.improve_bathing_rate as national_improve_bathing_rate,
        national.improve_breathing_rate as national_improve_breathing_rate,
        national.improve_drug_taking_rate as national_improve_drug_taking_rate,
        national.pressure_ulcer_rate as national_pressure_ulcer_rate,
        national.medication_action_rate as national_medication_action_rate,
        national.major_falls_rate as national_major_falls_rate,
        national.discharge_function_rate as national_discharge_function_rate,
        national.transfer_hi_provider_rate as national_transfer_hi_provider_rate,
        national.transfer_hi_patient_rate as national_transfer_hi_patient_rate,
        national.dtc_national_observed_rate as national_dtc_observed_rate,
        national.ppr_national_observed_rate as national_ppr_observed_rate,
        national.pph_national_observed_rate as national_pph_observed_rate,
        national.medicare_spending_per_episode as national_medicare_spending_per_episode,
        vintage.as_of
    from agency
    cross join national
    cross join vintage

),

-- OASIS process/outcome measures: 13 measures, one row per agency
-- per measure. Rate is the reported percentage; numerator /
-- denominator are the case counts. Footnotes stay in staging.
oasis as (

    select
        ccn,
        'oasis' as measure_source,
        'timely_initiation' as measure_code,
        'How often the home health team began their patients care in a timely manner'
            as measure_name,
        timely_initiation_numerator as numerator,
        timely_initiation_denominator as denominator,
        cast(timely_initiation_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_timely_initiation_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'drug_education' as measure_code,
        'How often the home health team determined whether patients received'
        || ' a drug education on all medications provided during all episodes'
        || ' of care'
            as measure_name,
        drug_education_numerator as numerator,
        drug_education_denominator as denominator,
        cast(drug_education_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_drug_education_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'improve_ambulation' as measure_code,
        'How often patients got better at walking or moving around' as measure_name,
        improve_ambulation_numerator as numerator,
        improve_ambulation_denominator as denominator,
        cast(improve_ambulation_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_improve_ambulation_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'improve_bed_transferring' as measure_code,
        'How often patients got better at getting in and out of bed' as measure_name,
        improve_bed_transferring_numerator as numerator,
        improve_bed_transferring_denominator as denominator,
        cast(improve_bed_transferring_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_improve_bed_transferring_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'improve_bathing' as measure_code,
        'How often patients got better at bathing' as measure_name,
        improve_bathing_numerator as numerator,
        improve_bathing_denominator as denominator,
        cast(improve_bathing_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_improve_bathing_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'improve_breathing' as measure_code,
        'How often patients breathing improved' as measure_name,
        improve_breathing_numerator as numerator,
        improve_breathing_denominator as denominator,
        cast(improve_breathing_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_improve_breathing_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'improve_drug_taking' as measure_code,
        'How often patients got better at taking their drugs correctly by mouth'
            as measure_name,
        improve_drug_taking_numerator as numerator,
        improve_drug_taking_denominator as denominator,
        cast(improve_drug_taking_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_improve_drug_taking_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'pressure_ulcer' as measure_code,
        'Changes in skin integrity post-acute care: pressure ulcer / injury'
            as measure_name,
        pressure_ulcer_numerator as numerator,
        pressure_ulcer_denominator as denominator,
        cast(pressure_ulcer_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_pressure_ulcer_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'medication_action' as measure_code,
        'How often physician-recommended actions to address medication issues were completely timely'
            as measure_name,
        medication_action_numerator as numerator,
        medication_action_denominator as denominator,
        cast(medication_action_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_medication_action_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'major_falls' as measure_code,
        'Percent of residents experiencing one or more falls with major injury'
            as measure_name,
        major_falls_numerator as numerator,
        major_falls_denominator as denominator,
        cast(major_falls_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_major_falls_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'discharge_function' as measure_code,
        'Discharge function score' as measure_name,
        discharge_function_numerator as numerator,
        discharge_function_denominator as denominator,
        cast(discharge_function_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_discharge_function_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'transfer_hi_provider' as measure_code,
        'Transfer of health information to the provider at post-acute care'
            as measure_name,
        transfer_hi_provider_numerator as numerator,
        transfer_hi_provider_denominator as denominator,
        cast(transfer_hi_provider_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_transfer_hi_provider_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'oasis' as measure_source,
        'transfer_hi_patient' as measure_code,
        'Transfer of health information to the patient at post-acute care'
            as measure_name,
        transfer_hi_patient_numerator as numerator,
        transfer_hi_patient_denominator as denominator,
        cast(transfer_hi_patient_rate as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_transfer_hi_patient_rate as decimal(10, 3)) as national_value,
        as_of
    from base

),

-- Claims-based measures (DTC / PPR / PPH). Kept as one row per
-- measure with the risk-standardized rate as `score`; the observed
-- rate, CI bounds, and `performance_category` companions ride
-- alongside on the same row rather than exploding into extra rows,
-- since they describe the same underlying measurement.
-- `national_value` is the national observed rate CMS publishes for
-- each measure (CMS does not publish a risk-standardized national
-- rate, so the comparison is against observed).
claims as (

    select
        ccn,
        'claims' as measure_source,
        'dtc' as measure_code,
        'Discharge to community (percentage of patients discharged home who'
        || ' did not have an unplanned readmission or die within 31 days)'
            as measure_name,
        dtc_numerator as numerator,
        dtc_denominator as denominator,
        cast(dtc_risk_standardized_rate as decimal(10, 3)) as score,
        cast(dtc_observed_rate as decimal(10, 3)) as observed_rate,
        cast(dtc_risk_standardized_rate as decimal(10, 3)) as risk_standardized_rate,
        cast(dtc_risk_standardized_rate_lower as decimal(10, 3))
            as risk_standardized_rate_lower,
        cast(dtc_risk_standardized_rate_upper as decimal(10, 3))
            as risk_standardized_rate_upper,
        dtc_performance_category as performance_category,
        cast(national_dtc_observed_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'claims' as measure_source,
        'ppr' as measure_code,
        'Potentially preventable 30-day post-discharge readmissions' as measure_name,
        ppr_numerator as numerator,
        ppr_denominator as denominator,
        cast(ppr_risk_standardized_rate as decimal(10, 3)) as score,
        cast(ppr_observed_rate as decimal(10, 3)) as observed_rate,
        cast(ppr_risk_standardized_rate as decimal(10, 3)) as risk_standardized_rate,
        cast(ppr_risk_standardized_rate_lower as decimal(10, 3))
            as risk_standardized_rate_lower,
        cast(ppr_risk_standardized_rate_upper as decimal(10, 3))
            as risk_standardized_rate_upper,
        ppr_performance_category as performance_category,
        cast(national_ppr_observed_rate as decimal(10, 3)) as national_value,
        as_of
    from base
    union all
    select
        ccn,
        'claims' as measure_source,
        'pph' as measure_code,
        'Potentially preventable hospitalizations during home health care'
            as measure_name,
        pph_numerator as numerator,
        pph_denominator as denominator,
        cast(pph_risk_standardized_rate as decimal(10, 3)) as score,
        cast(pph_observed_rate as decimal(10, 3)) as observed_rate,
        cast(pph_risk_standardized_rate as decimal(10, 3)) as risk_standardized_rate,
        cast(pph_risk_standardized_rate_lower as decimal(10, 3))
            as risk_standardized_rate_lower,
        cast(pph_risk_standardized_rate_upper as decimal(10, 3))
            as risk_standardized_rate_upper,
        pph_performance_category as performance_category,
        cast(national_pph_observed_rate as decimal(10, 3)) as national_value,
        as_of
    from base

),

-- Medicare-spending-per-episode index. Agency value and national
-- value are dimensionless ratios (national = 1.00 by construction);
-- `episodes_for_medicare_spending` rides alongside as the
-- denominator. Kept as its own `measure_source` so users filtering
-- for OASIS or claims measures don't accidentally aggregate an
-- index against percentages.
spending as (

    select
        ccn,
        'spending' as measure_source,
        'medicare_spending_per_episode' as measure_code,
        'How much Medicare spends on an episode of care at this agency'
        || ' compared to Medicare spending across all agencies nationally'
            as measure_name,
        cast(null as int) as numerator,
        episodes_for_medicare_spending as denominator,
        cast(medicare_spending_per_episode as decimal(10, 3)) as score,
        cast(null as decimal(10, 3)) as observed_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate,
        cast(null as decimal(10, 3)) as risk_standardized_rate_lower,
        cast(null as decimal(10, 3)) as risk_standardized_rate_upper,
        cast(null as varchar) as performance_category,
        cast(national_medicare_spending_per_episode as decimal(10, 3)) as national_value,
        as_of
    from base

),

final as (

    -- rows whose score is null (suppressed / too few cases) are kept
    -- so measure coverage per agency stays analyzable
    select * from oasis
    union all
    select * from claims
    union all
    select * from spending

)

select * from final
