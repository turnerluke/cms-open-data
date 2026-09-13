-- TODO: the by-geography-and-service source is a single
-- latest-vintage snapshot with no year column, so this fact has no
-- `service_year`. The snapshot vintage is exposed as `as_of`
-- (upstream `modified` date via stg_cms__dataset_vintages).

with staged as (

    select * from {{ ref('stg_cms__medicare_physician_by_geography_and_service') }}

),

national as (

    -- national roll-up: 13,463 rows, one per
    -- (hcpcs_code, place_of_service). Pulled out as a join target so
    -- every state row can carry its corresponding national benchmark
    -- inline — the same "attach national to each row" pattern used
    -- in `fct_drug_geography`, `fct_home_health_quality`, and
    -- `fct_hospice_cahps`. National rows themselves are kept in the
    -- fact (see the `union all` below) so the file remains lossless.
    select
        hcpcs_code,
        place_of_service,
        total_rendering_providers as national_total_rendering_providers,
        total_beneficiaries as national_total_beneficiaries,
        total_services as national_total_services,
        total_beneficiary_day_services
            as national_total_beneficiary_day_services,
        avg_submitted_charge as national_avg_submitted_charge,
        avg_medicare_allowed_amount as national_avg_medicare_allowed_amount,
        avg_medicare_payment_amount as national_avg_medicare_payment_amount,
        avg_medicare_standardized_amount
            as national_avg_medicare_standardized_amount
    from staged
    where geography_level = 'National'

),

state_level as (

    -- 254,887 state-level rows. Grain is (geography_code,
    -- hcpcs_code, place_of_service); 5 rows carry a NULL
    -- geography_code in the current vintage (all five E&M /
    -- psychotherapy codes CMS emitted as state-level aggregates
    -- without identifying the state) and are kept as-is. All 5 have
    -- a matching national row for their (hcpcs, pos) so benchmark
    -- columns populate on them; the `unique_combination_of_columns`
    -- grain test is NULL-safe on that row. The pseudo-codes 9A–9E
    -- (armed-forces / unknown / foreign) and territory codes 60 /
    -- 66 / 69 / 72 / 78 are ordinary state values here — 4,409 total
    -- rows across those ten codes.
    select
        st.geography_level,
        st.geography_code,
        st.geography_description,
        st.hcpcs_code,
        st.hcpcs_description,
        st.hcpcs_drug_indicator,
        st.place_of_service,

        -- state-level totals
        st.total_rendering_providers,
        st.total_beneficiaries,
        st.total_services,
        st.total_beneficiary_day_services,

        -- payment averages (per service)
        st.avg_submitted_charge,
        st.avg_medicare_allowed_amount,
        st.avg_medicare_payment_amount,
        st.avg_medicare_standardized_amount,

        -- national benchmark for the service, joined by
        -- (hcpcs_code, place_of_service). Every state row has a
        -- matching national row in the current vintage
        -- (0 orphans across 254,887 state rows), so these are
        -- populated on all State rows; they are NULL only on the
        -- National rows themselves.
        nat.national_total_rendering_providers,
        nat.national_total_beneficiaries,
        nat.national_total_services,
        nat.national_total_beneficiary_day_services,
        nat.national_avg_submitted_charge,
        nat.national_avg_medicare_allowed_amount,
        nat.national_avg_medicare_payment_amount,
        nat.national_avg_medicare_standardized_amount,

        -- share of national utilisation the state accounts for.
        -- Sum of state shares within a (hcpcs, pos) can be less than
        -- 1 because CMS drops (npi, hcpcs, pos) cells with <=10
        -- beneficiaries from the underlying provider file — those
        -- volumes are counted in the national row but not in any
        -- state row.
        st.total_services
        / nullif(
            nat.national_total_services, 0
        ) as share_of_national_services,
        cast(st.total_beneficiaries as double)
        / nullif(
            nat.national_total_beneficiaries, 0
        ) as share_of_national_beneficiaries,

        -- per-unit ratios
        st.avg_medicare_payment_amount
        / nullif(
            st.avg_submitted_charge, 0
        ) as payment_to_charge_ratio,
        st.avg_medicare_payment_amount
        / nullif(
            st.avg_medicare_allowed_amount, 0
        ) as payment_to_allowed_ratio
    from staged as st
    left join national as nat
        on
            st.hcpcs_code = nat.hcpcs_code
            and st.place_of_service = nat.place_of_service
    where st.geography_level = 'State'

),

national_level as (

    -- Keep the 13,463 national rows in the fact so the file is
    -- lossless: national totals themselves are addressable at
    -- `geography_level = 'National'` and don't need to be recovered
    -- by summing states (which would miss the sub-11 suppression
    -- tail — 22.4% of program-wide services). National rows carry
    -- NULL in every `national_*` benchmark column — their own
    -- values live in the plain metric columns — and their
    -- `geography_code` is NULL by design (CMS omits it).
    select
        geography_level,
        cast(null as varchar) as geography_code,
        geography_description,
        hcpcs_code,
        hcpcs_description,
        hcpcs_drug_indicator,
        place_of_service,

        total_rendering_providers,
        total_beneficiaries,
        total_services,
        total_beneficiary_day_services,

        avg_submitted_charge,
        avg_medicare_allowed_amount,
        avg_medicare_payment_amount,
        avg_medicare_standardized_amount,

        -- benchmark columns are NULL on national rows themselves
        cast(null as bigint) as national_total_rendering_providers,
        cast(null as bigint) as national_total_beneficiaries,
        cast(null as double) as national_total_services,
        cast(null as double) as national_total_beneficiary_day_services,
        cast(null as double) as national_avg_submitted_charge,
        cast(null as double) as national_avg_medicare_allowed_amount,
        cast(null as double) as national_avg_medicare_payment_amount,
        cast(null as double) as national_avg_medicare_standardized_amount,
        cast(null as double) as share_of_national_services,
        cast(null as double) as share_of_national_beneficiaries,

        avg_medicare_payment_amount
        / nullif(
            avg_submitted_charge, 0
        ) as payment_to_charge_ratio,
        avg_medicare_payment_amount
        / nullif(
            avg_medicare_allowed_amount, 0
        ) as payment_to_allowed_ratio
    from staged
    where geography_level = 'National'

),

combined as (

    select
        geography_level,
        geography_code,
        geography_description,
        hcpcs_code,
        hcpcs_description,
        hcpcs_drug_indicator,
        place_of_service,
        total_rendering_providers,
        total_beneficiaries,
        total_services,
        total_beneficiary_day_services,
        avg_submitted_charge,
        avg_medicare_allowed_amount,
        avg_medicare_payment_amount,
        avg_medicare_standardized_amount,
        national_total_rendering_providers,
        national_total_beneficiaries,
        national_total_services,
        national_total_beneficiary_day_services,
        national_avg_submitted_charge,
        national_avg_medicare_allowed_amount,
        national_avg_medicare_payment_amount,
        national_avg_medicare_standardized_amount,
        share_of_national_services,
        share_of_national_beneficiaries,
        payment_to_charge_ratio,
        payment_to_allowed_ratio
    from state_level
    union all
    select
        geography_level,
        geography_code,
        geography_description,
        hcpcs_code,
        hcpcs_description,
        hcpcs_drug_indicator,
        place_of_service,
        total_rendering_providers,
        total_beneficiaries,
        total_services,
        total_beneficiary_day_services,
        avg_submitted_charge,
        avg_medicare_allowed_amount,
        avg_medicare_payment_amount,
        avg_medicare_standardized_amount,
        national_total_rendering_providers,
        national_total_beneficiaries,
        national_total_services,
        national_total_beneficiary_day_services,
        national_avg_submitted_charge,
        national_avg_medicare_allowed_amount,
        national_avg_medicare_payment_amount,
        national_avg_medicare_standardized_amount,
        share_of_national_services,
        share_of_national_beneficiaries,
        payment_to_charge_ratio,
        payment_to_allowed_ratio
    from national_level

),

final as (

    select
        combined.*,
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
    from combined

)

select * from final
