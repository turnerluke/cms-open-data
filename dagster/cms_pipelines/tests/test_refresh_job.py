"""Tests for the full-refresh job, its schedule, and extract->dbt wiring.

The job is only meaningful if the dbt assets actually sit downstream of
the extraction assets — the `DbtProjectComponent` translation in
`defs/cms_analytics/defs.yaml` maps each dbt source table onto the
extraction asset of the same name. These tests pin that wiring alongside
the job/schedule definitions so a regression in either shows up here.
"""

import json
from pathlib import Path

from cms_pipelines.definitions import defs
from cms_pipelines.defs.jobs import FULL_REFRESH_CRON

from dagster import AssetKey, Definitions


def _selected_keys(definitions: Definitions) -> set[str]:
    """Asset keys (as user strings) the full-refresh job will materialize."""
    job = definitions.resolve_job_def("full_refresh_job")
    return {key.to_user_string() for key in job.asset_layer.executable_asset_keys}


def test_full_refresh_job_resolves() -> None:
    """The job resolves from the loaded Definitions by name."""
    job = defs().resolve_job_def("full_refresh_job")
    assert job.name == "full_refresh_job"


def test_full_refresh_job_covers_extraction_and_dbt_assets() -> None:
    """`AssetSelection.all()` picks up both extraction assets and dbt models."""
    definitions = defs()
    selected = _selected_keys(definitions)

    all_keys = {key.to_user_string() for key in definitions.resolve_asset_graph().get_all_asset_keys()}
    assert selected == all_keys

    extraction = {key for key in selected if key.startswith("cms_")}
    dbt_models = {key for key in selected if "/" in key}
    assert extraction, "expected cms_* extraction assets in the job selection"
    assert dbt_models, "expected dbt model assets in the job selection"


def test_dbt_models_are_downstream_of_extraction_assets() -> None:
    """Dbt staging models depend on the extraction assets, not detached specs.

    Without the source-key translation, dbt sources resolve to external
    `cms_raw/<table>` specs and the job would run extraction and dbt as
    two disconnected islands.
    """
    graph = defs().resolve_asset_graph()
    all_keys = {key.to_user_string() for key in graph.get_all_asset_keys()}
    assert not {key for key in all_keys if key.startswith("cms_raw/")}, (
        "dbt sources resolved to detached cms_raw/* specs; the defs.yaml translation is broken"
    )

    staging = AssetKey.from_user_string("staging/stg_cms__hospital_general_information")
    parents = {key.to_user_string() for key in graph.get(staging).parent_keys}
    assert parents == {"cms_hospital_general_information"}


def test_dbt_source_tables_match_extraction_assets() -> None:
    """Every dbt source table has an extraction asset of the same name.

    The defs.yaml translation renames source keys to `node.name`, so the
    graph only connects when `gen_cms_sources.py` (table names) and
    `registry_assets.py` (asset names) derive identical `cms_*` names
    from the registry. A mismatch here localizes the failure that
    otherwise only shows up as an opaque set difference in the job
    coverage test.
    """
    manifest = json.loads(
        (Path(__file__).resolve().parents[3] / "dbt" / "cms_analytics" / "target" / "manifest.json").read_text()
    )
    source_tables = {node["name"] for node in manifest["sources"].values()}

    graph = defs().resolve_asset_graph()
    extraction = {key.to_user_string() for key in graph.get_all_asset_keys() if key.to_user_string().startswith("cms_")}
    assert source_tables == extraction


def test_full_refresh_schedule_targets_job_weekly() -> None:
    """The schedule runs the full-refresh job on the expected weekly cron."""
    schedule = defs().resolve_schedule_def("full_refresh_schedule")
    assert schedule.job.name == "full_refresh_job"
    assert schedule.cron_schedule == FULL_REFRESH_CRON
    assert schedule.cron_schedule == "0 5 * * 1"
    assert schedule.execution_timezone == "UTC"
