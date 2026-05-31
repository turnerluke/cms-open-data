"""Top-level Dagster entry point: load every definition under defs/."""

from pathlib import Path

from dagster import Definitions, definitions, load_from_defs_folder


@definitions
def defs() -> Definitions:
    """Recursively load assets, jobs, resources, sensors, and schedules from defs/."""
    return load_from_defs_folder(path_within_project=Path(__file__).parent)
