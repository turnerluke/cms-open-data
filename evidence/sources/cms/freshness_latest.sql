-- Per-dataset latest freshness state, with a display-friendly row-count
-- bucket and a coalesced upstream date so the DataTable / BarChart
-- components can render rows whose publisher exposes no `modified`
-- date without dropping them. Sortable by any raw column; the bucket
-- and sort keys support the "row-count landscape" chart on the page.
select
    dataset_key,
    asset_name,
    source_family,
    run_date,
    captured_at,
    days_since_capture,
    modified,
    days_since_upstream_modified,
    row_count,
    row_count_delta,
    n_runs,
    n_distinct_modified,
    schema_changed,
    case
        when row_count < 100 then '<100'
        when row_count < 1000 then '100–999'
        when row_count < 10000 then '1K–9.9K'
        when row_count < 100000 then '10K–99.9K'
        when row_count < 1000000 then '100K–999K'
        when row_count < 10000000 then '1M–9.9M'
        else '10M+'
    end as row_count_bucket,
    case
        when row_count < 100 then 1
        when row_count < 1000 then 2
        when row_count < 10000 then 3
        when row_count < 100000 then 4
        when row_count < 1000000 then 5
        when row_count < 10000000 then 6
        else 7
    end as row_count_bucket_sort
from main_marts.fct_dataset_freshness
