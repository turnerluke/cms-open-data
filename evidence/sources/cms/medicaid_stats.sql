-- Warehouse-coverage roll-up for the `Medicaid drug utilization`
-- section of the site index. Single-row extract to keep parity with
-- the pattern used by `prescriber_stats.sql`, `hospice_stats.sql`, etc.
select
    (select count(*) from main_marts.fct_medicaid_drug_state)
        as drug_state_rows,
    (
        select count(*)
        from main_marts.fct_medicaid_drug_state
        where not is_state_tier
    ) as national_rows,
    (
        select count(*)
        from main_marts.fct_medicaid_drug_state
        where is_state_tier
    ) as state_rows,
    (
        select count(distinct state)
        from main_marts.fct_medicaid_drug_state
        where is_state_tier
    ) as states,
    (select count(*) from main_marts.fct_medicaid_medicare_drug_spend)
        as program_compare_rows,
    (select max(as_of) from main_marts.fct_medicaid_drug_state) as as_of
