"""Raw-extraction asset for CMS Socrata datasets."""

from cms_api import iter_part_d_spending_by_drug
import pyarrow as pa

from dagster import AssetExecutionContext, asset


@asset(
    io_manager_key="parquet_io_manager",
    group_name="cms_raw",
    compute_kind="cms_api",
    description=(
        "Full extract of CMS Socrata dataset `mhdd-npjx` (Medicare Part D "
        "Spending by Drug). One row per drug; year-suffixed spending and "
        "dosage-unit columns flow through as Pydantic extras."
    ),
)
def cms_part_d_spending_by_drug(context: AssetExecutionContext) -> pa.Table:
    """Stream every row of the Part D Spending by Drug dataset into Parquet."""
    rows = [model.model_dump(mode="json") for model in iter_part_d_spending_by_drug()]
    if not rows:
        msg = "Part D Spending by Drug returned zero rows; refusing to land empty Parquet"
        raise RuntimeError(msg)
    context.log.info("Fetched %d Part D drug rows", len(rows))
    return pa.Table.from_pylist(rows)
