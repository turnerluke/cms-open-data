"""Raw-extraction assets for Healthcare.gov content endpoints."""

from cms_api import get_articles, get_glossary
import pyarrow as pa

from dagster import AssetExecutionContext, asset


@asset(
    io_manager_key="cms_raw_io_manager",
    group_name="cms_raw",
    compute_kind="cms_api",
    description=("Healthcare.gov glossary terms — full corpus from `https://www.healthcare.gov/api/glossary.json`."),
)
def cms_healthcare_gov_glossary(context: AssetExecutionContext) -> pa.Table:
    """Fetch the full Healthcare.gov glossary into Parquet."""
    rows = [term.model_dump(mode="json") for term in get_glossary()]
    if not rows:
        msg = "Healthcare.gov glossary returned zero terms; refusing to land empty Parquet"
        raise RuntimeError(msg)
    context.log.info("Fetched %d Healthcare.gov glossary terms", len(rows))
    return pa.Table.from_pylist(rows)


@asset(
    io_manager_key="cms_raw_io_manager",
    group_name="cms_raw",
    compute_kind="cms_api",
    description=("Healthcare.gov article corpus — full extract from `https://www.healthcare.gov/api/articles.json`."),
)
def cms_healthcare_gov_articles(context: AssetExecutionContext) -> pa.Table:
    """Fetch the full Healthcare.gov article corpus into Parquet."""
    rows = [article.model_dump(mode="json") for article in get_articles()]
    if not rows:
        msg = "Healthcare.gov articles returned zero records; refusing to land empty Parquet"
        raise RuntimeError(msg)
    context.log.info("Fetched %d Healthcare.gov articles", len(rows))
    return pa.Table.from_pylist(rows)
