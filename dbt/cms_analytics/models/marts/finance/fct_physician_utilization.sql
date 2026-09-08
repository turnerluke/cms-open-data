-- TODO: the physician-by-provider source file is a single
-- latest-vintage snapshot with no year column, so this fact has no
-- spending_year. The snapshot vintage is exposed as `as_of` (upstream
-- `modified` date via stg_cms__dataset_vintages); moving to an npi ×
-- year grain still needs the claims year, which the vintage alone
-- doesn't give.

with staged as (

    select * from {{ ref('stg_cms__medicare_physician_by_provider') }}

),

final as (

    select
        -- identifier / grain (one row per rendering NPI)
        npi,

        -- entity code: 'I' individual clinician, 'O' organizational
        -- biller. The FK to `dim_clinician` is filtered on `'I'` — see
        -- the yml for why organizational NPIs are excluded from the
        -- relationships test rather than reported as orphans.
        entity_code,

        -- provider descriptors (kept for at-a-glance lookups without
        -- joining dim_clinician; richer roster attributes live there)
        provider_last_org_name,
        provider_first_name,
        provider_credentials,
        provider_type,
        state,
        medicare_participating_indicator,

        -- overall Part B utilization and payments (one snapshot row
        -- per NPI — these top-line totals are never suppressed)
        total_hcpcs_codes,
        total_beneficiaries,
        total_services,
        total_submitted_charges,
        total_medicare_allowed_amount,
        total_medicare_payment_amount,
        total_medicare_standardized_amount,

        -- drug (Part B drug administrations) split. Suppression
        -- indicators pass through so downstream can distinguish
        -- "no drug activity" (all totals null with no indicator) from
        -- CMS-suppressed rows ('*' below disclosure threshold, '#'
        -- counter-suppressed so cannot be recalculated). Nothing is
        -- coalesced to 0.
        drug_suppression_indicator,
        drug_total_hcpcs_codes,
        drug_total_beneficiaries,
        drug_total_services,
        drug_submitted_charges,
        drug_medicare_allowed_amount,
        drug_medicare_payment_amount,
        drug_medicare_standardized_amount,

        -- medical (non-drug) split with the same suppression scheme
        medical_suppression_indicator,
        medical_total_hcpcs_codes,
        medical_total_beneficiaries,
        medical_total_services,
        medical_submitted_charges,
        medical_medicare_allowed_amount,
        medical_medicare_payment_amount,
        medical_medicare_standardized_amount,

        -- beneficiary demographics and risk
        avg_beneficiary_age,
        beneficiary_dual_count,
        beneficiary_nondual_count,
        beneficiary_dual_count
        / nullif(
            beneficiary_dual_count + beneficiary_nondual_count, 0
        ) as pct_beneficiaries_dual_eligible,
        avg_hcc_risk_score,

        -- select chronic-condition prevalences (share of the
        -- provider's beneficiaries with the condition). The upstream
        -- CMS source publishes these as integer percents on a 0-100
        -- scale and caps them at 75 for privacy; we divide by 100.0
        -- here so every `pct_*` column in this mart is a 0-1
        -- fraction on the same scale as `pct_beneficiaries_dual_eligible`
        -- — see the yml `accepted_range` tests. The full 25-column
        -- staging set is trimmed to a representative mix of
        -- high-impact physical and behavioral conditions — pull
        -- additional columns from staging when needed.
        pct_beneficiaries_diabetes / 100.0 as pct_beneficiaries_diabetes,
        pct_beneficiaries_hypertension / 100.0 as pct_beneficiaries_hypertension,
        pct_beneficiaries_hyperlipidemia / 100.0 as pct_beneficiaries_hyperlipidemia,
        pct_beneficiaries_ischemic_heart_disease
        / 100.0 as pct_beneficiaries_ischemic_heart_disease,
        pct_beneficiaries_heart_failure_nonihd
        / 100.0 as pct_beneficiaries_heart_failure_nonihd,
        pct_beneficiaries_copd / 100.0 as pct_beneficiaries_copd,
        pct_beneficiaries_chronic_kidney_disease
        / 100.0 as pct_beneficiaries_chronic_kidney_disease,
        pct_beneficiaries_cancer6 / 100.0 as pct_beneficiaries_cancer6,
        pct_beneficiaries_alzheimers_dementia
        / 100.0 as pct_beneficiaries_alzheimers_dementia,
        pct_beneficiaries_depression / 100.0 as pct_beneficiaries_depression,
        pct_beneficiaries_anxiety / 100.0 as pct_beneficiaries_anxiety,
        pct_beneficiaries_alcohol_drug_use
        / 100.0 as pct_beneficiaries_alcohol_drug_use,

        -- derived per-unit metrics
        total_medicare_payment_amount
        / nullif(total_services, 0) as medicare_payment_per_service,
        total_medicare_payment_amount
        / nullif(total_beneficiaries, 0) as medicare_payment_per_beneficiary,
        total_services
        / nullif(total_beneficiaries, 0) as services_per_beneficiary,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'medicare_physician_by_provider'
        ) as as_of
    from staged

)

select * from final
