---
title: Data quality
---

Every deploy of this site is preceded by a full `dbt build` against
the DuckDB warehouse: every model rebuilt, every schema/relationship
test executed. The results are captured by
`scripts/publish_dbt_run_results.py` into a `dbt_run_results` table
in the warehouse itself, so this page can report the actual health of
the models the deployed site queries — not a badge on a README.

```sql stats
select
    models,
    tests,
    passes,
    warns,
    failures,
    skipped,
    total_seconds,
    generated_at
from cms.dq_stats
```

<BigValue data={stats} value=models title="Models built" fmt=num0 />
<BigValue data={stats} value=tests title="Tests executed" fmt=num0 />
<BigValue data={stats} value=passes title="Passes" fmt=num0 />
<BigValue data={stats} value=warns title="Warns" fmt=num0 />
<BigValue data={stats} value=failures title="Failures / errors" fmt=num0 />

## How to read this page

Each row in `dbt_run_results` is one node from the last `dbt build` —
model, test, seed, or snapshot — with its status, execution time, and
(for tests) the model it covers via `depends_on.nodes`. The rollups
below are queries over that table. Numbers reflect the run that
produced this deployment: `generated_at` is
<Value data={stats} column=generated_at fmt=longdate />; total
build time was
<Value data={stats} column=total_seconds fmt=num1 /> seconds across
<Value data={stats} column=models fmt=num0 /> models and
<Value data={stats} column=tests fmt=num0 /> tests.

## Per-model results

Every model with its build status and the outcome of every test
attributed to it (via the first `model.*` unique_id in the test's
`depends_on.nodes`). Sorted so any model carrying a `warn` or a
`fail` floats to the top.

```sql models
select
    model,
    model_status,
    execution_time,
    tests_total,
    tests_passed,
    tests_warned,
    tests_failed
from cms.dq_model_results
```

<DataTable data={models} rows=20 search=true>
  <Column id=model title="Model" wrap=true />
  <Column id=model_status title="Status" />
  <Column id=execution_time title="Build (s)" fmt=num2 />
  <Column id=tests_total title="Tests" fmt=num0 />
  <Column id=tests_passed title="Passed" fmt=num0 />
  <Column id=tests_warned title="Warned" fmt=num0 />
  <Column id=tests_failed title="Failed" fmt=num0 />
</DataTable>

## Slowest models

Top 15 models by build-time execution. Useful for spotting expensive
nodes and week-over-week regressions.

```sql slowest
select model, status, execution_time
from cms.dq_slowest_models
```

<BarChart
  data={slowest}
  x=model
  y=execution_time
  swapXY=true
  title="Slowest models (seconds)"
  yFmt=num2
/>

<DataTable data={slowest} rows=15>
  <Column id=model title="Model" wrap=true />
  <Column id=status title="Status" />
  <Column id=execution_time title="Build (s)" fmt=num2 />
</DataTable>

## Test-outcome rollup

Node counts per (resource type, status), plus one summary row counting
models with no attributed test.

```sql coverage
select resource_type, status, nodes
from cms.dq_test_coverage
```

<DataTable data={coverage} rows=20>
  <Column id=resource_type title="Resource type" />
  <Column id=status title="Status" />
  <Column id=nodes title="Nodes" fmt=num0 />
</DataTable>

## Known limitations and parked decisions

- **`dim_drug` matches on names only.** The core `dim_drug` mart
  conforms Medicare Part B and Part D drug rows on upper-trimmed
  brand and generic names, stripping the trailing `*` marker CMS
  appends when a source row aggregates brand + generic (or
  manufacturer) variants. That gets almost every clean match, but
  differently formatted names — dosage-qualified Part B strings,
  multi-brand HCPCS rows — still fall through. A future iteration
  could map both sources to RxNorm ingredient codes; the TODO at
  the top of `dbt/cms_analytics/models/marts/core/dim_drug.sql`
  records that scope decision.
- **RxNorm mapping is deferred, not planned.** The RxNorm-ingredient-
  code route was considered against the current name-only join and
  parked — it would add an upstream dependency, a maintenance
  surface, and a mapping-quality caveat, in exchange for smoothing
  a small tail of unmatched rows. Reopening it is a scope decision,
  not a bug.
- **No NDC↔dim_drug bridge.** Medicaid State Drug Utilization is
  keyed by NDC (11-digit National Drug Code); Medicare Part B and
  Part D spending are keyed by drug name (HCPCS-adjacent for Part B,
  brand + generic for Part D). No bridge from NDC to
  `dim_drug.drug_key` exists in the warehouse, so Medicaid and
  Medicare drug spending are compared at the program grain
  (`fct_medicaid_medicare_drug_spend`) rather than joined at the
  drug grain. Building an NDC → RxNorm → drug-name bridge is a
  larger effort than this warehouse has spent, and would inherit
  every caveat of the RxNorm mapping above.

## Caveats

- **Point-in-time snapshot.** Every count above reflects the specific
  `dbt build` that produced this deployment — not the live state of
  the source data or of any subsequent local run. `generated_at`
  (<Value data={stats} column=generated_at fmt=longdate />) is the
  moment those artifacts were written.
- **Standing warns are known gaps, not regressions.** The
  <Value data={stats} column=warns fmt=num0 /> warn-severity failures
  are expected to be `relationships` tests that assert clinician /
  hospital / prescriber CCN or NPI foreign keys resolve into their
  dimension tables (a warn from any other test family would be a
  regression worth investigating, not a known gap); upstream CMS
  files carry legitimate rows whose identifiers
  don't reconcile back to the canonical dimension (retired CCNs,
  cross-namespace identifiers, non-clinician recipients on the Open
  Payments file). Those tests are kept at warn severity deliberately
  so the build stays green while the gap stays visible on this page.
  See `_core__models.yml` / `_finance__models.yml` for the
  test-level context.
- **Counts drift with the data.** Model, test, and warn counts change
  as new models land and as upstream CMS files add or lose rows. This
  page shows the numbers as they were at the last successful
  warehouse build — treat any week-over-week change as data-driven
  unless a PR touched the model/test surface.
