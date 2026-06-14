"""Raw-extraction asset for NPPES NPI-2 (organizational) providers.

The NPPES API has no bulk export — only per-NPI lookup and a search endpoint
capped at 1,200 reachable rows per query. To get a usable provider sample we
sweep the search endpoint state-by-state, restricted to organizational
providers (`enumeration_type='NPI-2'`). Each state stays well under the cap
for most jurisdictions; this is not exhaustive coverage.
"""

from cms_api import search_providers
import pyarrow as pa

from dagster import AssetExecutionContext, Config, asset


US_STATES = (
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL",
    "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
    "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
    "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
    "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",
    "WY",
)  # fmt: skip


class NppesProvidersConfig(Config):
    """Configuration for the NPPES provider sweep.

    Override `states` from the Dagster UI to restrict a dev run to a
    handful of states; the default is all 50 US states plus DC.
    """

    states: list[str] = list(US_STATES)  # noqa: RUF012 -- pydantic Config copies defaults per-instance


@asset(
    io_manager_key="cms_raw_io_manager",
    group_name="cms_raw",
    compute_kind="cms_api",
    description=(
        "NPPES NPI-2 (organizational) providers, swept state-by-state via the "
        "NPI Registry search endpoint. Each state subquery is capped at 1,200 "
        "reachable rows by the API; coverage is therefore not exhaustive."
    ),
)
def cms_nppes_providers(
    context: AssetExecutionContext,
    config: NppesProvidersConfig,
) -> pa.Table:
    """Sweep NPPES organizational providers and land them as Parquet."""
    rows: list[dict[str, object]] = []
    for state in config.states:
        state_rows = [provider.model_dump(mode="json") for provider in search_providers(enumeration_type="NPI-2", state=state)]
        context.log.info("Fetched %d NPPES NPI-2 providers from %s", len(state_rows), state)
        rows.extend(state_rows)
    if not rows:
        msg = "NPPES sweep returned zero providers; refusing to land empty Parquet"
        raise RuntimeError(msg)
    return pa.Table.from_pylist(rows)
