"""Warehouse-wide refresh job and its weekly schedule.

``full_refresh_job`` selects every asset in the graph — all `cms_*`
extraction assets plus every dbt model downstream of them (the
`DbtProjectComponent` maps dbt sources onto the extraction asset keys,
so one run materializes extract -> staging -> marts in dependency
order). The job is launchable ad hoc from the UI/CLI, and
``full_refresh_schedule`` runs it every Monday at 05:00 UTC — CMS
refreshes most datasets monthly, so weekly keeps the warehouse at most
a few days stale without hammering the APIs.
"""

from dagster import AssetSelection, Definitions, ScheduleDefinition, define_asset_job, definitions


FULL_REFRESH_CRON = "0 5 * * 1"

full_refresh_job = define_asset_job(
    name="full_refresh_job",
    selection=AssetSelection.all(),
    description=("Materialize the entire warehouse: every cms_* extraction asset, then every dbt model downstream of them."),
)

full_refresh_schedule = ScheduleDefinition(
    name="full_refresh_schedule",
    job=full_refresh_job,
    cron_schedule=FULL_REFRESH_CRON,
    execution_timezone="UTC",
    description="Weekly full-warehouse refresh, Mondays at 05:00 UTC.",
)


@definitions
def refresh_defs() -> Definitions:
    """Register the full-refresh job and its weekly schedule."""
    return Definitions(jobs=[full_refresh_job], schedules=[full_refresh_schedule])
