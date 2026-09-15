-- Grain: one row per dataset (latest ledger capture). The ledger is
-- append-only, so "latest" is defined by (`run_date` desc, `captured_at`
-- desc) — the tiebreaker matters only for multi-capture same-day runs.

with ledger as (

    select * from {{ ref('stg_cms__vintage_ledger') }}

),

with_prior as (

    select
        dataset_key,
        asset_name,
        source_family,
        run_date,
        captured_at,
        modified,
        row_count,
        schema_hash,
        lag(row_count) over (
            partition by dataset_key
            order by run_date, captured_at
        ) as prior_row_count,
        lag(schema_hash) over (
            partition by dataset_key
            order by run_date, captured_at
        ) as prior_schema_hash,
        row_number() over (
            partition by dataset_key
            order by run_date desc, captured_at desc
        ) as recency_rank
    from ledger

),

per_dataset_aggregates as (

    select
        dataset_key,
        count(*) as n_runs,
        count(distinct modified) as n_distinct_modified
    from ledger
    group by 1

),

latest as (

    select
        w.dataset_key,
        w.asset_name,
        w.source_family,
        w.run_date,
        w.captured_at,
        w.modified,
        w.row_count,
        w.schema_hash,
        w.prior_row_count,
        w.prior_schema_hash
    from with_prior as w
    where w.recency_rank = 1

)

select
    l.dataset_key,
    l.asset_name,
    l.source_family,

    -- freshness of the local capture itself
    l.run_date,
    l.captured_at,
    date_diff('day', l.run_date, current_date) as days_since_capture,

    -- freshness of the upstream data the capture describes
    l.modified,
    case
        when l.modified is null then null
        else date_diff('day', l.modified, current_date)
    end as days_since_upstream_modified,

    -- volume + drift signals vs the immediately-prior run
    l.row_count,
    case
        when l.prior_row_count is null then null
        else l.row_count - l.prior_row_count
    end as row_count_delta,

    agg.n_runs,
    agg.n_distinct_modified,
    case
        when l.prior_schema_hash is null then false
        else l.schema_hash <> l.prior_schema_hash
    end as schema_changed

from latest as l
inner join per_dataset_aggregates as agg
    on l.dataset_key = agg.dataset_key
