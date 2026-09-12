-- TODO: the by-provider prescriber file is a single latest-vintage
-- snapshot with no year column, so this profile has no
-- `prescribing_year`. The snapshot vintage is exposed as `as_of`
-- (upstream `modified` date via stg_cms__dataset_vintages); moving to
-- an npi × year grain still needs the claims year, which the vintage
-- alone doesn't give.

with staged as (

    select * from {{ ref('stg_cms__medicare_part_d_prescribers_by_provider') }}

),

final as (

    select
        -- identifier / grain (one row per prescriber NPI)
        npi,

        -- entity code: 'I' individual clinician (1,416,881 rows), 'O'
        -- organizational biller (2 rows). The FK to `dim_clinician` is
        -- filtered on `'I'` — see the yml for why organizational NPIs
        -- are excluded from the relationships test rather than
        -- reported as orphans.
        entity_code,

        -- prescriber descriptors (kept for at-a-glance lookups without
        -- joining dim_clinician; richer roster attributes live there)
        prescriber_last_org_name,
        prescriber_first_name,
        prescriber_middle_initial,
        prescriber_credentials,
        prescriber_type,
        prescriber_type_source,
        city,
        state,
        zip5,
        ruca_code,
        ruca_description,

        -- overall Part D prescribing totals (never suppressed; CMS
        -- drops NPIs with 10 or fewer total claims from the file
        -- entirely rather than suppressing in place)
        total_claims,
        total_30day_fills,
        total_drug_cost,
        total_day_supply,
        -- `total_beneficiaries` is separately suppressed (blank → NULL)
        -- when the count is 1–10; ~10% of rows null. No explicit flag
        -- column: total_beneficiaries is null iff CMS suppressed it.
        total_beneficiaries,

        -- brand vs generic vs other-drug splits. Each carries its
        -- suppression flag through so `NULL` from suppression is
        -- distinguishable from a prescriber with no activity in that
        -- category. Nothing is coalesced to 0.
        brand_suppression_flag,
        brand_total_claims,
        brand_total_drug_cost,
        generic_suppression_flag,
        generic_total_claims,
        generic_total_drug_cost,
        other_suppression_flag,
        other_total_claims,
        other_total_drug_cost,

        -- Medicare-Advantage-Part-D vs stand-alone-PDP splits
        mapd_suppression_flag,
        mapd_total_claims,
        mapd_total_drug_cost,
        pdp_suppression_flag,
        pdp_total_claims,
        pdp_total_drug_cost,

        -- Low-Income-Subsidy vs non-LIS splits
        lis_suppression_flag,
        lis_total_claims,
        lis_total_drug_cost,
        nonlis_suppression_flag,
        nonlis_total_claims,
        nonlis_total_drug_cost,

        -- opioid family. Unlike the splits above, opioid measure
        -- columns share no named suppression flag — the measure is
        -- `NULL` directly when CMS suppresses. `opioid_prescriber_rate`
        -- is CMS's opioid share of total claims on a 0-100 percent
        -- scale; the long-acting rate is additionally `NULL` when the
        -- prescriber has no long-acting opioid claims at all.
        opioid_total_claims,
        opioid_total_drug_cost,
        opioid_total_day_supply,
        opioid_total_beneficiaries,
        opioid_prescriber_rate,
        opioid_la_total_claims,
        opioid_la_total_drug_cost,
        opioid_la_total_day_supply,
        opioid_la_total_beneficiaries,
        opioid_la_prescriber_rate,

        -- antibiotic totals (same "measure NULL means suppressed"
        -- scheme as opioid; no separate flag column)
        antibiotic_total_claims,
        antibiotic_total_drug_cost,
        antibiotic_total_beneficiaries,

        -- antipsychotic totals for age-65-and-over. Two suppression
        -- flags with the standard `*` / `#` / NULL semantics.
        antipsychotic_ge65_suppression_flag,
        antipsychotic_ge65_total_claims,
        antipsychotic_ge65_total_drug_cost,
        antipsychotic_ge65_beneficiary_suppression_flag,
        antipsychotic_ge65_total_beneficiaries,

        -- beneficiary demographics and risk. `avg_beneficiary_age` is
        -- never null; `avg_hcc_risk_score` is null on 1 row. Sex /
        -- race / dual counts are pairwise-suppressed when the group is
        -- 1–10.
        avg_beneficiary_age,
        beneficiary_age_lt_65_count,
        beneficiary_age_65_74_count,
        beneficiary_age_75_84_count,
        beneficiary_age_gt_84_count,
        beneficiary_female_count,
        beneficiary_male_count,
        beneficiary_race_white_count,
        beneficiary_race_black_count,
        beneficiary_race_asian_pacific_islander_count,
        beneficiary_race_hispanic_count,
        beneficiary_race_native_american_count,
        beneficiary_race_other_count,
        beneficiary_dual_count,
        beneficiary_nondual_count,
        avg_hcc_risk_score,

        -- derived per-unit metrics. NULL when either input is NULL
        -- (suppressed beneficiary counts) or the denominator is 0.
        total_drug_cost / nullif(total_claims, 0) as cost_per_claim,
        total_drug_cost / nullif(total_beneficiaries, 0) as cost_per_beneficiary,
        total_drug_cost / nullif(total_day_supply, 0) as cost_per_day_supplied,
        total_claims
        / nullif(total_beneficiaries, 0) as claims_per_beneficiary,
        beneficiary_dual_count
        / nullif(
            beneficiary_dual_count + beneficiary_nondual_count, 0
        ) as pct_beneficiaries_dual_eligible,
        generic_total_claims
        / nullif(total_claims, 0) as pct_claims_generic,
        brand_total_claims
        / nullif(total_claims, 0) as pct_claims_brand,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'medicare_part_d_prescribers_by_provider'
        ) as as_of
    from staged

)

select * from final
