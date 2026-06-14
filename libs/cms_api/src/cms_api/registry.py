"""Declarative dataset registry.

Every CMS dataset the pipeline extracts is one row in
`libs/cms_api/datasets.toml`. This module loads those rows into typed
`DatasetSpec` objects; the Dagster project generates one asset per spec.
Adding a new dataset is a single TOML entry, not a new Python module.
"""

from __future__ import annotations

from pathlib import Path
import tomllib
from typing import TYPE_CHECKING, Literal

from pydantic import BaseModel, ConfigDict, model_validator


if TYPE_CHECKING:
    from ._types import JsonObject, JsonValue


# `libs/cms_api/src/cms_api/registry.py` -> `libs/cms_api/datasets.toml`.
_DATASETS_TOML = Path(__file__).resolve().parents[2] / "datasets.toml"

SourceLiteral = Literal["socrata", "healthcare_gov"]


class DatasetSpec(BaseModel):
    """One row from `datasets.toml`.

    Fields shared by every source live at the top level; source-specific
    fields (`dataset_id` for Socrata, `path` for healthcare.gov) are
    optional here and validated in `_validate_source_fields` so a malformed
    TOML row fails fast at load time rather than mid-asset-run.
    """

    model_config = ConfigDict(extra="forbid")

    key: str
    source: SourceLiteral
    description: str
    group: str
    dataset_id: str | None = None
    domain: str = "data.cms.gov"
    path: str | None = None

    @model_validator(mode="after")
    def _validate_source_fields(self) -> DatasetSpec:
        """Reject specs missing the field their `source` requires."""
        if self.source == "socrata":
            if not self.dataset_id:
                msg = f"socrata dataset {self.key!r} requires `dataset_id`"
                raise ValueError(msg)
            if self.path is not None:
                msg = f"socrata dataset {self.key!r} must not set `path`"
                raise ValueError(msg)
        elif self.source == "healthcare_gov":
            if not self.path:
                msg = f"healthcare_gov dataset {self.key!r} requires `path`"
                raise ValueError(msg)
            if self.dataset_id is not None:
                msg = f"healthcare_gov dataset {self.key!r} must not set `dataset_id`"
                raise ValueError(msg)
        return self


def load_registry(toml_path: Path | None = None) -> list[DatasetSpec]:
    """Load `datasets.toml` into validated `DatasetSpec` objects.

    Args:
        toml_path: Override the default `libs/cms_api/datasets.toml`
            location (used by tests).

    Returns:
        One `DatasetSpec` per `[[dataset]]` entry, in file order.

    """
    resolved = toml_path if toml_path is not None else _DATASETS_TOML
    with resolved.open("rb") as fp:
        loaded: JsonObject = tomllib.load(fp)
    entries: JsonValue = loaded.get("dataset", [])
    if not isinstance(entries, list):
        msg = f"datasets.toml: expected `[[dataset]]` array, got {type(entries).__name__}"
        raise TypeError(msg)
    return [DatasetSpec.model_validate(entry) for entry in entries]
