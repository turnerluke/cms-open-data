"""Raw-data extraction assets for the CMS-family public APIs.

Each module here defines one Dagster asset that fetches a dataset via the
`cms_api` library and lands it as Parquet under `data/raw/<asset>/`. The
dbt `cms_analytics` project reads those Parquet trees in place via
DuckDB's `external_location`; nothing here transforms the data.
"""
