-- TODO: the geography-and-drug source is a single latest-vintage
-- snapshot with no year column, so this fact has no
-- `prescribing_year`. The snapshot vintage is exposed as `as_of`
-- (upstream `modified` date via stg_cms__dataset_vintages).

with staged as (

    select * from {{ ref('stg_cms__medicare_part_d_prescribers_by_geography_and_drug') }}

),

national as (

    -- national roll-up: 3,632 rows, one per (brand_name, generic_name).
    -- Pulled out as a join target so every state row can carry its
    -- corresponding national benchmark inline — the same "attach
    -- national to each provider row" pattern used in
    -- `fct_home_health_quality` and `fct_hospice_cahps`. National rows
    -- themselves are kept in the fact (see the `union all` below) so
    -- the file remains lossless.
    select
        brand_name,
        generic_name,
        total_prescribers as national_total_prescribers,
        total_claims as national_total_claims,
        total_30day_fills as national_total_30day_fills,
        total_drug_cost as national_total_drug_cost,
        total_beneficiaries as national_total_beneficiaries,
        lis_beneficiary_cost_share as national_lis_beneficiary_cost_share,
        nonlis_beneficiary_cost_share
            as national_nonlis_beneficiary_cost_share
    from staged
    where geography_level = 'National'

),

state_level as (

    -- 114,029 state-level rows. Grain is (geography_code,
    -- brand_name, generic_name); one row in the current vintage ships
    -- a NULL geography_code / geography_description
    -- (Trazodone Hcl in the RY26 file) and is kept as-is — the
    -- expression_is_true grain test in the yml handles it.
    select
        st.geography_level,
        st.geography_code,
        st.geography_description,
        st.brand_name,
        st.generic_name,
        -- key expression must stay identical to dim_drug's so the
        -- relationship holds
        {{
            dbt_utils.generate_surrogate_key(
                ["upper(st.brand_name)", "upper(st.generic_name)"]
            )
        }} as drug_key,

        -- state-level totals
        st.total_prescribers,
        st.total_claims,
        st.total_30day_fills,
        st.total_drug_cost,
        st.total_beneficiaries,

        -- age-65-and-over subset. Paired-null semantics enforced by
        -- upstream staging expression tests.
        st.ge65_suppression_flag,
        st.ge65_total_claims,
        st.ge65_total_30day_fills,
        st.ge65_total_drug_cost,
        st.ge65_beneficiary_suppression_flag,
        st.ge65_total_beneficiaries,

        -- LIS / non-LIS beneficiary cost-share (dollars); never NULL
        st.lis_beneficiary_cost_share,
        st.nonlis_beneficiary_cost_share,

        -- drug-class flags, boolean-cast in staging. Same value on
        -- every row for a given (brand_name, generic_name).
        st.is_opioid,
        st.is_long_acting_opioid,
        st.is_antibiotic,
        st.is_antipsychotic,

        -- national benchmark for the drug, joined by (brand, generic).
        -- Every state (brand, generic) pair has a matching national
        -- row, so these are populated on all State rows; they are NULL
        -- only on the National rows themselves.
        nat.national_total_prescribers,
        nat.national_total_claims,
        nat.national_total_30day_fills,
        nat.national_total_drug_cost,
        nat.national_total_beneficiaries,
        nat.national_lis_beneficiary_cost_share,
        nat.national_nonlis_beneficiary_cost_share,

        -- share of national utilization the state accounts for
        st.total_claims
        / nullif(nat.national_total_claims, 0) as share_of_national_claims,
        st.total_drug_cost
        / nullif(
            nat.national_total_drug_cost, 0
        ) as share_of_national_cost,

        -- per-unit costs
        st.total_drug_cost / nullif(st.total_claims, 0) as cost_per_claim,
        st.total_drug_cost / nullif(
            st.total_beneficiaries, 0
        ) as cost_per_beneficiary
    from staged as st
    left join national as nat
        on
            st.brand_name = nat.brand_name
            and st.generic_name = nat.generic_name
    where st.geography_level = 'State'

),

national_level as (

    -- Keep the 3,632 national rows in the fact so the file is
    -- lossless: national totals themselves are addressable at
    -- `geography_level = 'National'` and don't need to be recovered by
    -- summing states (which would double-count the pseudo-code cells
    -- 9A–9E). National rows carry NULL in every `national_*`
    -- benchmark column — their own values live in the plain metric
    -- columns.
    select
        geography_level,
        cast(null as varchar) as geography_code,
        geography_description,
        brand_name,
        generic_name,
        {{
            dbt_utils.generate_surrogate_key(
                ["upper(brand_name)", "upper(generic_name)"]
            )
        }} as drug_key,

        total_prescribers,
        total_claims,
        total_30day_fills,
        total_drug_cost,
        total_beneficiaries,

        ge65_suppression_flag,
        ge65_total_claims,
        ge65_total_30day_fills,
        ge65_total_drug_cost,
        ge65_beneficiary_suppression_flag,
        ge65_total_beneficiaries,

        lis_beneficiary_cost_share,
        nonlis_beneficiary_cost_share,

        is_opioid,
        is_long_acting_opioid,
        is_antibiotic,
        is_antipsychotic,

        -- benchmark columns are NULL on national rows themselves
        cast(null as bigint) as national_total_prescribers,
        cast(null as bigint) as national_total_claims,
        cast(null as double) as national_total_30day_fills,
        cast(null as double) as national_total_drug_cost,
        cast(null as bigint) as national_total_beneficiaries,
        cast(null as double) as national_lis_beneficiary_cost_share,
        cast(null as double) as national_nonlis_beneficiary_cost_share,
        cast(null as double) as share_of_national_claims,
        cast(null as double) as share_of_national_cost,

        total_drug_cost / nullif(total_claims, 0) as cost_per_claim,
        total_drug_cost / nullif(
            total_beneficiaries, 0
        ) as cost_per_beneficiary
    from staged
    where geography_level = 'National'

),

combined as (

    select
        geography_level,
        geography_code,
        geography_description,
        brand_name,
        generic_name,
        drug_key,
        total_prescribers,
        total_claims,
        total_30day_fills,
        total_drug_cost,
        total_beneficiaries,
        ge65_suppression_flag,
        ge65_total_claims,
        ge65_total_30day_fills,
        ge65_total_drug_cost,
        ge65_beneficiary_suppression_flag,
        ge65_total_beneficiaries,
        lis_beneficiary_cost_share,
        nonlis_beneficiary_cost_share,
        is_opioid,
        is_long_acting_opioid,
        is_antibiotic,
        is_antipsychotic,
        national_total_prescribers,
        national_total_claims,
        national_total_30day_fills,
        national_total_drug_cost,
        national_total_beneficiaries,
        national_lis_beneficiary_cost_share,
        national_nonlis_beneficiary_cost_share,
        share_of_national_claims,
        share_of_national_cost,
        cost_per_claim,
        cost_per_beneficiary
    from state_level
    union all
    select
        geography_level,
        geography_code,
        geography_description,
        brand_name,
        generic_name,
        drug_key,
        total_prescribers,
        total_claims,
        total_30day_fills,
        total_drug_cost,
        total_beneficiaries,
        ge65_suppression_flag,
        ge65_total_claims,
        ge65_total_30day_fills,
        ge65_total_drug_cost,
        ge65_beneficiary_suppression_flag,
        ge65_total_beneficiaries,
        lis_beneficiary_cost_share,
        nonlis_beneficiary_cost_share,
        is_opioid,
        is_long_acting_opioid,
        is_antibiotic,
        is_antipsychotic,
        national_total_prescribers,
        national_total_claims,
        national_total_30day_fills,
        national_total_drug_cost,
        national_total_beneficiaries,
        national_lis_beneficiary_cost_share,
        national_nonlis_beneficiary_cost_share,
        share_of_national_claims,
        share_of_national_cost,
        cost_per_claim,
        cost_per_beneficiary
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
                = 'medicare_part_d_prescribers_by_geography_and_drug'
        ) as as_of
    from combined

)

select * from final
