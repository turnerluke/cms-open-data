-- TODO: the by-geography-and-service source file is a single
-- latest-vintage snapshot with no year column, so this fact has no
-- `service_year`. The snapshot vintage is exposed as `as_of` (upstream
-- `modified` date via stg_cms__dataset_vintages); moving to an
-- (hcpcs, pos, year) grain still needs the claims year, which the
-- vintage alone doesn't give.

-- Service / HCPCS-level rollup at (hcpcs_code, place_of_service).
-- Sourced from the National rows of
-- `stg_cms__medicare_physician_by_geography_and_service` — the
-- CMS-published all-USA aggregate — rather than aggregating the
-- 9.78M-row by-provider-and-service file. The two disagree because
-- CMS drops (npi, hcpcs, pos) rows with 10 or fewer beneficiaries
-- from the provider file (dropped, not suppressed in place). The
-- gap is material: summing `total_services` across the provider
-- file recovers 2,756,663,769 of the National-row total
-- 3,554,240,899, i.e. 77.6% — 22.4% of national service volume
-- lives entirely in the sub-11 suppression tail and is only
-- available from the National rollup.

with staged as (

    select * from {{ ref('stg_cms__medicare_physician_by_geography_and_service') }}

),

national as (

    -- 13,463 National rows in the current vintage — one per
    -- (hcpcs_code, place_of_service) combination. Grain uniqueness
    -- is inherited from the upstream stg model's
    -- `unique_combination_of_columns` test and re-asserted in the
    -- yml below.
    select
        hcpcs_code,
        place_of_service,
        hcpcs_description,
        -- 'Y' Part-B drug HCPCS (814 National rows across 699
        -- distinct drug codes), 'N' medical service (12,649 rows,
        -- 8,704 distinct codes). Constant per hcpcs_code
        -- (verified: 0 codes carry >1 indicator across their
        -- F/O National rows).
        hcpcs_drug_indicator,

        -- utilization
        total_rendering_providers,
        total_beneficiaries,
        total_services,
        total_beneficiary_day_services,

        -- payment averages (per service). `avg_submitted_charge` is
        -- NOT right-censored at the National level — the
        -- $99,999.99 cap is a per-provider reporting-file artifact
        -- (18 provider rows hit it out of 9.78M); the National
        -- aggregate max is $78,725.07 in the current vintage.
        avg_submitted_charge,
        avg_medicare_allowed_amount,
        avg_medicare_payment_amount,
        avg_medicare_standardized_amount,

        -- Derived payment-vs-charge gaps. Both denominators are
        -- non-null on every row upstream, so these never null on
        -- zero-division grounds; guarded with `nullif` for defence
        -- in depth.
        avg_medicare_payment_amount
        / nullif(avg_submitted_charge, 0) as payment_to_charge_ratio,
        avg_medicare_allowed_amount
        / nullif(avg_submitted_charge, 0) as allowed_to_charge_ratio,
        avg_medicare_payment_amount
        / nullif(
            avg_medicare_allowed_amount, 0
        ) as payment_to_allowed_ratio,

        -- Beneficiaries per rendering provider — measures how
        -- concentrated the service is. Never null (both inputs
        -- non-null).
        cast(total_beneficiaries as double)
        / nullif(
            total_rendering_providers, 0
        ) as beneficiaries_per_provider,

        -- Services per beneficiary — a utilisation intensity
        -- proxy. Never null.
        total_services
        / nullif(total_beneficiaries, 0) as services_per_beneficiary
    from staged
    where geography_level = 'National'

),

final as (

    select
        national.*,
        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where
                vintages.dataset_key
                = 'medicare_physician_by_geography_and_service'
        ) as as_of
    from national

)

select * from final
