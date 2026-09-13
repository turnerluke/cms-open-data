-- Medicaid state drug utilization rolled up from the quarterly
-- (utilization_type, state, ndc, quarter) staging grain to a
-- (state, ndc, calendar_year) grain, with FFS vs MCO carried as
-- side-by-side column families. The 4 quarters of 2023 fold into one
-- annual row per (state, ndc).
--
-- Suppression semantics: staging blanks out all five measure columns
-- when 1-10 prescriptions were dispensed; suppression_used is TRUE on
-- those rows. `sum()` skips nulls, so a suppressed quarter simply
-- doesn't contribute to the annual total — no coalescing to 0. Two
-- disclosure counters carry the missingness signal forward per util
-- type: quarters_reported (1-4) and disclosed_quarters (0-4).
--
-- Tier convention (inherited from staging): state='XX' is the CMS
-- national-aggregate tier that re-adds state-suppressed values;
-- state <> 'XX' is the state-level tier. Downstream must filter to
-- one or the other and never mix — XX >= sum(states) always. National
-- tier: 53,205 (state=XX, ndc) rows. State tier: 1,201,587 rows
-- (across 52 state codes: 50 states + DC + PR).

with staged as (

    select * from {{ ref('stg_cms__medicaid_state_drug_utilization') }}

),

ffs as (

    -- Fee-for-service channel. 2,539,160 staging rows fold into
    -- 842,347 (state, ndc, year) rows.
    select
        state,
        ndc,
        labeler_code,
        product_code,
        package_size,
        calendar_year,
        count(*) as ffs_quarters_reported,
        sum(case when not suppression_used then 1 else 0 end)
            as ffs_disclosed_quarters,
        sum(units_reimbursed) as ffs_units_reimbursed,
        sum(number_of_prescriptions) as ffs_number_of_prescriptions,
        sum(total_amount_reimbursed) as ffs_total_amount_reimbursed,
        sum(medicaid_amount_reimbursed) as ffs_medicaid_amount_reimbursed,
        sum(non_medicaid_amount_reimbursed) as ffs_non_medicaid_amount_reimbursed
    from staged
    where utilization_type = 'FFSU'
    group by 1, 2, 3, 4, 5, 6

),

mco as (

    -- Managed-care organization channel. 2,787,426 staging rows fold
    -- into 899,468 (state, ndc, year) rows.
    select
        state,
        ndc,
        labeler_code,
        product_code,
        package_size,
        calendar_year,
        count(*) as mco_quarters_reported,
        sum(case when not suppression_used then 1 else 0 end)
            as mco_disclosed_quarters,
        sum(units_reimbursed) as mco_units_reimbursed,
        sum(number_of_prescriptions) as mco_number_of_prescriptions,
        sum(total_amount_reimbursed) as mco_total_amount_reimbursed,
        sum(medicaid_amount_reimbursed) as mco_medicaid_amount_reimbursed,
        sum(non_medicaid_amount_reimbursed) as mco_non_medicaid_amount_reimbursed
    from staged
    where utilization_type = 'MCOU'
    group by 1, 2, 3, 4, 5, 6

),

combined as (

    -- Full outer join: 487,023 (state, ndc, year) combos appear in
    -- both channels, 355,324 in FFS only, 412,445 in MCO only,
    -- totalling 1,254,792 pivoted rows. `coalesce` on the grain
    -- columns preserves either side's key values.
    select
        coalesce(ffs.state, mco.state) as state,
        coalesce(ffs.ndc, mco.ndc) as ndc,
        coalesce(ffs.labeler_code, mco.labeler_code) as labeler_code,
        coalesce(ffs.product_code, mco.product_code) as product_code,
        coalesce(ffs.package_size, mco.package_size) as package_size,
        coalesce(ffs.calendar_year, mco.calendar_year) as calendar_year,

        -- state tier flag: TRUE for the 52 state codes,
        -- FALSE for the national CMS-aggregate row `'XX'`. Downstream
        -- filters use this instead of the raw code to avoid mixing
        -- tiers by accident.
        coalesce(ffs.state, mco.state) <> 'XX' as is_state_tier,

        -- FFS channel
        ffs.ffs_quarters_reported,
        ffs.ffs_disclosed_quarters,
        ffs.ffs_units_reimbursed,
        ffs.ffs_number_of_prescriptions,
        ffs.ffs_total_amount_reimbursed,
        ffs.ffs_medicaid_amount_reimbursed,
        ffs.ffs_non_medicaid_amount_reimbursed,

        -- MCO channel
        mco.mco_quarters_reported,
        mco.mco_disclosed_quarters,
        mco.mco_units_reimbursed,
        mco.mco_number_of_prescriptions,
        mco.mco_total_amount_reimbursed,
        mco.mco_medicaid_amount_reimbursed,
        mco.mco_non_medicaid_amount_reimbursed,

        -- Combined-channel totals. `coalesce(_, 0)` on each side is
        -- safe here because we want channel absence to add zero, not
        -- null-out the sum; a suppressed quarter still contributes
        -- nothing (its input was null) but a channel that reported
        -- some quarters and had others suppressed still contributes
        -- the disclosed portion. Rows where BOTH channels are fully
        -- null keep null combined totals so "no data reported" stays
        -- distinguishable from "reported zero".
        case
            when
                ffs.ffs_total_amount_reimbursed is null
                and mco.mco_total_amount_reimbursed is null
                then null
            else
                coalesce(ffs.ffs_total_amount_reimbursed, 0)
                + coalesce(mco.mco_total_amount_reimbursed, 0)
        end as total_amount_reimbursed,
        case
            when
                ffs.ffs_medicaid_amount_reimbursed is null
                and mco.mco_medicaid_amount_reimbursed is null
                then null
            else
                coalesce(ffs.ffs_medicaid_amount_reimbursed, 0)
                + coalesce(mco.mco_medicaid_amount_reimbursed, 0)
        end as medicaid_amount_reimbursed,
        case
            when
                ffs.ffs_non_medicaid_amount_reimbursed is null
                and mco.mco_non_medicaid_amount_reimbursed is null
                then null
            else
                coalesce(ffs.ffs_non_medicaid_amount_reimbursed, 0)
                + coalesce(mco.mco_non_medicaid_amount_reimbursed, 0)
        end as non_medicaid_amount_reimbursed,
        case
            when
                ffs.ffs_number_of_prescriptions is null
                and mco.mco_number_of_prescriptions is null
                then null
            else
                coalesce(ffs.ffs_number_of_prescriptions, 0)
                + coalesce(mco.mco_number_of_prescriptions, 0)
        end as number_of_prescriptions,
        case
            when
                ffs.ffs_units_reimbursed is null
                and mco.mco_units_reimbursed is null
                then null
            else
                coalesce(ffs.ffs_units_reimbursed, 0)
                + coalesce(mco.mco_units_reimbursed, 0)
        end as units_reimbursed
    from ffs
    full outer join mco
        on
            ffs.state = mco.state
            and ffs.ndc = mco.ndc
            and ffs.calendar_year = mco.calendar_year

),

final as (

    select
        combined.*,

        -- MCO share of combined Medicaid reimbursement. Nullifies
        -- when the combined total is null or zero so the ratio stays
        -- meaningful and never divides by zero.
        combined.mco_medicaid_amount_reimbursed / nullif(
            combined.medicaid_amount_reimbursed, 0
        ) as mco_share_of_medicaid_amount,

        -- Per-prescription cost, computed from the combined channel
        -- totals. Divides by zero → null so any downstream mean stays
        -- honest.
        combined.total_amount_reimbursed / nullif(
            combined.number_of_prescriptions, 0
        ) as cost_per_prescription,

        -- Snapshot vintage: upstream `modified` date of the SDUD
        -- source file. Scalar subquery so a missing sidecar surfaces
        -- as null (caught by the not_null test) instead of losing
        -- rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where
                vintages.dataset_key = 'medicaid_state_drug_utilization_2023'
        ) as as_of
    from combined

)

select * from final
