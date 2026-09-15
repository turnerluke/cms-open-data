-- Freshness aggregates by `source_family`. Answers: how many datasets
-- does each extraction family cover, how stale the family's upstream
-- captures run on average, and how much data volume does each pull in.
select
    source_family,
    count(*) as datasets,
    sum(row_count) as total_rows,
    min(days_since_upstream_modified) as freshest_upstream_days,
    max(days_since_upstream_modified) as stalest_upstream_days,
    round(avg(days_since_upstream_modified), 1)
        as avg_upstream_age_days,
    min(modified) as oldest_modified,
    max(modified) as newest_modified
from main_marts.fct_dataset_freshness
group by source_family
order by datasets desc, source_family
