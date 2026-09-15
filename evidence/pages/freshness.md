---
title: Dataset freshness
---

Every weekly warehouse build appends one row per CMS dataset to a
durable JSONL ledger at `data/vintages/ledger.jsonl` — capture time,
upstream `modified` / `issued` / `released` dates, Parquet row and
byte counts, and a schema hash. Because the ledger is committed
to the repo, this history survives the ephemeral raw-data teardown
each CI run does, and the mart at `fct_dataset_freshness` can answer
three questions on top of it: how fresh is each dataset today, when
did the upstream publisher last touch it, and what has changed
between runs.

```sql stats
select
    datasets_tracked,
    source_families,
    total_rows,
    ledger_rows,
    earliest_run_date,
    latest_run_date,
    oldest_upstream_modified,
    newest_upstream_modified,
    datasets_without_modified,
    datasets_schema_changed,
    max_n_runs
from cms.freshness_stats
```

<BigValue data={stats} value=datasets_tracked title="Datasets tracked" fmt=num0 />
<BigValue data={stats} value=source_families title="Source families" fmt=num0 />
<BigValue data={stats} value=total_rows title="Rows across all datasets" fmt=num0 />
<BigValue data={stats} value=ledger_rows title="Ledger rows on file" fmt=num0 />

## How to read this page today

The ledger currently holds
<Value data={stats} column=ledger_rows fmt=num0 /> rows — exactly one
per dataset, from the initial backfill captured between
<Value data={stats} column=earliest_run_date fmt=longdate /> and
<Value data={stats} column=latest_run_date fmt=longdate />. Every
dataset therefore reports `n_runs = 1`, `row_count_delta = NULL`, and
`schema_changed = false`; the mart is designed to be the same shape
after ten or a hundred rebuilds, so this page will fill in with
between-run signal as weekly appends accrue. Sections below say
truthfully what the ledger shows now, not what future runs will show.

## Per-dataset latest state

The primary view: for each dataset, the latest `run_date`, when the
upstream publisher last modified the data, days since each of those,
and the Parquet-footer row count. `days_since_capture` and
`days_since_upstream_modified` are computed at build time against
`current_date`, not at query time — the numbers age on disk between
weekly rebuilds. `healthcare_gov_glossary` is the sole dataset with
no upstream `modified` date; its publisher exposes none.

```sql latest
select
    dataset_key,
    source_family,
    run_date,
    days_since_capture,
    modified,
    days_since_upstream_modified,
    row_count,
    n_runs
from cms.freshness_latest
order by days_since_upstream_modified desc nulls last
```

<DataTable data={latest} rows=43 search=true>
  <Column id=dataset_key title="Dataset" wrap=true />
  <Column id=source_family title="Source family" />
  <Column id=run_date title="Run date" fmt=shortdate />
  <Column id=days_since_capture title="Days since capture" fmt=num0 />
  <Column id=modified title="Upstream modified" fmt=shortdate />
  <Column id=days_since_upstream_modified title="Days since upstream" fmt=num0 />
  <Column id=row_count title="Rows" fmt=num0 />
  <Column id=n_runs title="Runs" fmt=num0 />
</DataTable>

## Coverage by source family

The 43 datasets group into six extraction families. `dkan_provider_data`
(the CMS Care Compare provider files) is the largest cohort;
`dkan_data_api_bulk` (spending-and-utilization bulk feeds) accounts for
most of the aggregate row count. Upstream freshness varies markedly
across families — the QHP landscape files (`dkan_healthcare_gov_zip`)
are the freshest cohort at an average of about 32 days since publisher
`modified`, while the bulk fact tables are the oldest, averaging over
100 days.

```sql by_family
select
    source_family,
    datasets,
    total_rows,
    freshest_upstream_days,
    stalest_upstream_days,
    avg_upstream_age_days
from cms.freshness_by_family
```

<BarChart
  data={by_family}
  x=source_family
  y=datasets
  swapXY=true
  title="Datasets per source family"
  yFmt=num0
/>

<DataTable data={by_family} rows=10>
  <Column id=source_family title="Source family" />
  <Column id=datasets title="Datasets" fmt=num0 />
  <Column id=total_rows title="Rows" fmt=num0 />
  <Column id=freshest_upstream_days title="Freshest (days)" fmt=num0 />
  <Column id=stalest_upstream_days title="Stalest (days)" fmt=num0 />
  <Column id=avg_upstream_age_days title="Avg age (days)" fmt=num1 />
</DataTable>

## Upstream publication window

The current backfill captures upstream `modified` dates ranging from
<Value data={stats} column=oldest_upstream_modified fmt=longdate />
(the HRRP and VBP annual releases) to
<Value data={stats} column=newest_upstream_modified fmt=longdate />
(one of the individual-market QHP landscape files). About half of
tracked datasets have an upstream `modified` in the last two months;
the annual releases sit in the "over 180 days" bucket by design and
won't refresh until CMS republishes.

```sql upstream_age
select
    case
        when days_since_upstream_modified is null then 'null (no upstream date)'
        when days_since_upstream_modified <= 30 then '<= 30d'
        when days_since_upstream_modified <= 60 then '31–60d'
        when days_since_upstream_modified <= 90 then '61–90d'
        when days_since_upstream_modified <= 180 then '91–180d'
        else '> 180d'
    end as bucket,
    case
        when days_since_upstream_modified is null then 6
        when days_since_upstream_modified <= 30 then 1
        when days_since_upstream_modified <= 60 then 2
        when days_since_upstream_modified <= 90 then 3
        when days_since_upstream_modified <= 180 then 4
        else 5
    end as sort_order,
    count(*) as datasets
from cms.freshness_latest
group by 1, 2
order by sort_order
```

<BarChart
  data={upstream_age}
  x=bucket
  y=datasets
  title="Datasets by upstream-modified age"
  sort=false
  yFmt=num0
/>

## Row-count landscape

Dataset sizes span eight orders of magnitude — from
`home_health_national` at one row (a national roll-up) to
`medicare_part_d_prescribers_by_provider_and_drug` at roughly 28
million rows. Because BarChart doesn't expose a log y-axis on this
Evidence build, the section shows two views: a bucketed distribution
across decades, and the top ten datasets by raw row count.

```sql row_count_buckets
select
    row_count_bucket,
    sort_order,
    datasets,
    total_rows
from cms.freshness_row_count_buckets
order by sort_order
```

<BarChart
  data={row_count_buckets}
  x=row_count_bucket
  y=datasets
  title="Datasets by row-count bucket"
  sort=false
  yFmt=num0
/>

```sql top_row_counts
select dataset_key, source_family, row_count
from cms.freshness_latest
order by row_count desc
limit 10
```

<DataTable data={top_row_counts} rows=10>
  <Column id=dataset_key title="Dataset" wrap=true />
  <Column id=source_family title="Source family" />
  <Column id=row_count title="Rows" fmt=num0 />
</DataTable>

## Change tracking (fills in over time)

The mart carries three between-run signals — `row_count_delta`,
`schema_changed`, and `n_distinct_modified` — but each needs at least
two ledger rows for a given dataset to say anything. Today every
dataset has `n_runs = 1`, so the first two columns are `NULL` /
`false` for the whole table by construction and there is nothing to
plot. `n_distinct_modified` counts distinct non-null upstream dates
observed to date; today that's exactly one for every dataset except
`healthcare_gov_glossary` (whose publisher exposes no `modified`
date, so it stays at zero). As weekly builds append, this section
will grow the distributions and comparisons that only history can
answer.

```sql change_tracking
select
    case when schema_changed then 'schema changed' else 'schema unchanged' end
        as schema_status,
    n_runs,
    n_distinct_modified,
    count(*) as datasets
from cms.freshness_latest
group by 1, 2, 3
order by n_runs desc, n_distinct_modified desc
```

<DataTable data={change_tracking} rows=10>
  <Column id=schema_status title="Schema" />
  <Column id=n_runs title="Runs recorded" fmt=num0 />
  <Column id=n_distinct_modified title="Distinct upstream modifieds" fmt=num0 />
  <Column id=datasets title="Datasets" fmt=num0 />
</DataTable>

## Caveats

- **Single-run backfill.** The ledger's
  <Value data={stats} column=ledger_rows fmt=num0 /> rows all come from
  the initial backfill between
  <Value data={stats} column=earliest_run_date fmt=longdate /> and
  <Value data={stats} column=latest_run_date fmt=longdate />. `run_date`
  reflects the day each dataset's sidecar was captured, not a uniform
  release schedule; from now on the weekly warehouse job appends one
  row per dataset per run. `row_count_delta`, `schema_changed`, and
  the distribution of `n_runs` fill in as history accrues.
- **Upstream `modified` is CMS metadata.** The `modified` column comes
  from the publisher's own dataset metadata (DKAN, healthcare.gov,
  etc.) — it can lag or lead the moment the underlying data actually
  changed, and one publisher
  (<Value data={stats} column=datasets_without_modified fmt=num0 />
  dataset: `healthcare_gov_glossary`) exposes no `modified` date at
  all. Treat "days since upstream modified" as the metadata age, not
  the data-content age.
- **Build-time staleness.** `days_since_capture` and
  `days_since_upstream_modified` are computed against `current_date`
  at dbt build time, not query time, so the numbers age on disk
  between weekly rebuilds. Interpret them as "days since capture as
  of the last successful warehouse build".
- **Row counts are Parquet-footer sums.** `row_count` sums Parquet
  `num_rows` across the files that make up each dataset at capture
  time. It counts raw rows in the staging extract — not distinct
  entities, not post-dedupe mart rows, not filtered scopes — so it
  is best read as data-volume signal, not analytical population size.
- **Bot-PR cadence.** Weekly builds publish the ledger back to `main`
  via a bot pull request, so the committed ledger this page reads
  can trail the deployed site by up to a week if the PR hasn't
  merged yet. The mart is rebuilt on every deploy, so the deployed
  page and the mart-on-disk always agree, but both can predate the
  most recent uncommitted capture.
