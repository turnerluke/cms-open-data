-- Row-count landscape: dataset counts by decade-of-magnitude bucket.
-- Standing in for a log-scale bar chart, since Evidence's BarChart
-- component doesn't expose a y-log option on this version.
with buckets as (
    select
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
        end as sort_order,
        row_count
    from main_marts.fct_dataset_freshness
)
select
    row_count_bucket,
    sort_order,
    count(*) as datasets,
    sum(row_count) as total_rows
from buckets
group by row_count_bucket, sort_order
order by sort_order
