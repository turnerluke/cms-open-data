-- Pass-through: per-dataset latest freshness state from
-- `fct_dataset_freshness`. Grain: one row per dataset_key.
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
    schema_changed
from main_marts.fct_dataset_freshness
