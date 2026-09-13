-- National program-level drug-spend comparison between Medicaid
-- (State Drug Utilization Data, both FFS and MCO channels) and
-- Medicare (Part D pharmacy + Part B provider-administered). One row
-- per (calendar_year, program_name). Deliberately aggregate-only:
-- SDUD keys drugs by NDC while the Medicare Part D and Part B files
-- key by brand/generic name and have no NDC, so no reliable
-- drug-level join exists between the two programs (see
-- _finance__models.yml for the measured match rates that justified
-- this choice).
--
-- Row set for 2023 (the only year SDUD ships in the current vintage):
--   Medicaid FFS   — SDUD, state='XX', utilization_type='FFSU'
--   Medicaid MCO   — SDUD, state='XX', utilization_type='MCOU'
--   Medicaid Total — SDUD, state='XX', both channels combined
--   Medicare Part D — stg_cms__part_d_spending_by_drug,
--                     manufacturer_name = 'Overall'
--   Medicare Part B — stg_cms__medicare_part_b_spending_by_drug
--                     (program-wide, no manufacturer breakdown)
--
-- Each row carries `total_spending`, `total_claims`, and
-- `total_beneficiaries` when the source publishes them; a column is
-- null on programs where the source doesn't expose that measure.
-- Medicare Part B and Part D also carry `total_dosage_units`;
-- Medicaid instead reports `units_reimbursed` (package units), which
-- is not comparable across NDCs — so this mart leaves the field null
-- for Medicaid rows rather than stuff a non-comparable number into
-- the same column.
--
-- Medicare Part D `total_beneficiaries` from the 'Overall' rows is
-- CMS's own reported unique-beneficiary count and is NOT the sum of
-- per-manufacturer rows (drug-level de-duplication happens upstream).

with medicaid as (

    -- National tier only — `state='XX'` is the CMS unsuppressed
    -- national aggregate that re-adds state-suppressed values. Never
    -- sum this with `state != 'XX'` rows.
    select
        calendar_year,
        utilization_type,
        sum(total_amount_reimbursed) as total_spending,
        sum(number_of_prescriptions) as total_claims
    from {{ ref('stg_cms__medicaid_state_drug_utilization') }}
    where state = 'XX'
    group by 1, 2

),

medicaid_split as (

    select
        calendar_year,
        case utilization_type
            when 'FFSU' then 'Medicaid FFS'
            when 'MCOU' then 'Medicaid MCO'
        end as program_name,
        total_spending,
        total_claims
    from medicaid

),

medicaid_total as (

    select
        calendar_year,
        'Medicaid Total' as program_name,
        sum(total_spending) as total_spending,
        sum(total_claims) as total_claims
    from medicaid
    group by 1

),

part_d as (

    -- Manufacturer roll-up rows only, to avoid double-counting the
    -- per-manufacturer detail.
    select
        2023 as calendar_year,
        'Medicare Part D' as program_name,
        sum(total_spending_2023) as total_spending,
        sum(total_claims_2023) as total_claims,
        sum(total_beneficiaries_2023) as total_beneficiaries,
        sum(total_dosage_units_2023) as total_dosage_units
    from {{ ref('stg_cms__part_d_spending_by_drug') }}
    where manufacturer_name = 'Overall'

),

part_b as (

    select
        2023 as calendar_year,
        'Medicare Part B' as program_name,
        sum(total_spending_2023) as total_spending,
        sum(total_claims_2023) as total_claims,
        sum(total_beneficiaries_2023) as total_beneficiaries,
        sum(total_dosage_units_2023) as total_dosage_units
    from {{ ref('stg_cms__medicare_part_b_spending_by_drug') }}

),

combined as (

    select
        calendar_year,
        program_name,
        total_spending,
        total_claims,
        cast(null as double) as total_beneficiaries,
        cast(null as double) as total_dosage_units
    from medicaid_split
    union all
    select
        calendar_year,
        program_name,
        total_spending,
        total_claims,
        cast(null as double) as total_beneficiaries,
        cast(null as double) as total_dosage_units
    from medicaid_total
    union all
    select
        calendar_year,
        program_name,
        total_spending,
        total_claims,
        total_beneficiaries,
        total_dosage_units
    from part_d
    union all
    select
        calendar_year,
        program_name,
        total_spending,
        total_claims,
        total_beneficiaries,
        total_dosage_units
    from part_b

),

final as (

    select
        calendar_year,
        program_name,
        case
            when program_name like 'Medicaid%' then 'Medicaid'
            else 'Medicare'
        end as payer,
        total_spending,
        total_claims,
        total_beneficiaries,
        total_dosage_units,

        -- Per-claim cost. Definitions differ across programs (Medicaid
        -- "claim" = prescription; Medicare Part D "claim" = fill;
        -- Medicare Part B "claim" = line item), so this is loosely
        -- comparable at best. `null` when either input is null.
        total_spending / nullif(total_claims, 0) as spending_per_claim,

        -- Snapshot vintages of the three underlying files, exposed so
        -- consumers see how fresh each row is. Same scalar-subquery
        -- pattern as fct_hospital_utilization.
        case
            when program_name like 'Medicaid%'
                then (
                    select vintages.modified
                    from {{ ref('stg_cms__dataset_vintages') }} as vintages
                    where
                        vintages.dataset_key
                        = 'medicaid_state_drug_utilization_2023'
                )
            when program_name = 'Medicare Part D'
                then (
                    select vintages.modified
                    from {{ ref('stg_cms__dataset_vintages') }} as vintages
                    where vintages.dataset_key = 'part_d_spending_by_drug'
                )
            when program_name = 'Medicare Part B'
                then (
                    select vintages.modified
                    from {{ ref('stg_cms__dataset_vintages') }} as vintages
                    where
                        vintages.dataset_key
                        = 'medicare_part_b_spending_by_drug'
                )
        end as as_of
    from combined

)

select * from final
