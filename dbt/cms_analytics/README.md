# cms_analytics

dbt transformations for the CMS open-data lakehouse, materialized in a
local DuckDB file at `../../data/warehouse.duckdb`.

## Layout

- `models/staging/` — typed/renamed columns over raw bronze Parquet
  (sources defined via DuckDB `external_location` against
  `../../data/bronze/`).
- `models/intermediate/` — ephemeral joins/reshape helpers.
- `models/marts/` — analytical tables (core entities + subject-area
  marts).
- `dbt_tests/` — singular dbt tests. Named `dbt_tests/` rather than
  `tests/` so it doesn't collide with the repo-wide pytest-standards
  check that requires every `tests/` directory to have `__init__.py`.

## First-time setup

The sqlfluff dbt templater needs `dbt_packages/` to exist before it can
compile models, so install dbt packages once after cloning:

```bash
cd dbt/cms_analytics
uv run dbt deps --profiles-dir .
```

## Day-to-day commands

All commands assume `cd dbt/cms_analytics` and `--profiles-dir .`:

```bash
uv run dbt parse --profiles-dir . --target ci      # validate refs/sources
uv run dbt compile --profiles-dir . --target ci    # render SQL to target/
uv run dbt run --profiles-dir .                    # materialize against dev DuckDB
uv run dbt test --profiles-dir .                   # run schema + singular tests
uv run sqlfluff lint models/                       # SQL style check
uv run sqlfluff fix models/                        # auto-fix where possible
```

## Profiles

`profiles.yml` defines three targets:

- `dev` — writes to `../../data/warehouse.duckdb` (gitignored).
- `ci` — `:memory:` DuckDB; used by `dbt parse`/`dbt compile` and the
  sqlfluff dbt templater in CI.
- `prod` — reads the warehouse path from `$CMS_WAREHOUSE_PATH`, falling
  back to the dev path.

## Concurrency caveat

DuckDB is single-writer. If `dagster dev` materializes assets that write
to `data/warehouse.duckdb` while a local `dbt run` is also writing, one
side will block on the file lock. Run them serially.
