-- Headline aggregates over `fct_dataset_freshness` for the top-of-page
-- BigValues and the caveats block. All scalars — one row.
select
    (select count(*) from main_marts.fct_dataset_freshness)
        as datasets_tracked,
    (
        select count(distinct source_family)
        from main_marts.fct_dataset_freshness
    ) as source_families,
    (select sum(row_count) from main_marts.fct_dataset_freshness)
        as total_rows,
    (select sum(n_runs) from main_marts.fct_dataset_freshness)
        as ledger_rows,
    (select min(run_date) from main_marts.fct_dataset_freshness)
        as earliest_run_date,
    (select max(run_date) from main_marts.fct_dataset_freshness)
        as latest_run_date,
    (select min(modified) from main_marts.fct_dataset_freshness)
        as oldest_upstream_modified,
    (select max(modified) from main_marts.fct_dataset_freshness)
        as newest_upstream_modified,
    (
        select count(*) from main_marts.fct_dataset_freshness
        where modified is null
    ) as datasets_without_modified,
    (
        select count(*) from main_marts.fct_dataset_freshness
        where schema_changed
    ) as datasets_schema_changed,
    (
        select max(n_runs) from main_marts.fct_dataset_freshness
    ) as max_n_runs
