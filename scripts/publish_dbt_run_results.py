"""Publish dbt ``run_results.json`` as a warehouse table.

The Evidence data-quality page reads a row-per-node table
(``dbt_run_results``) with each model/test/seed/snapshot's status,
execution time, failures count, and parent-model attribution for tests.
This script materializes that table from the dbt artifacts left in
``target/`` after a run.

Test parent attribution: dbt tests declare their parents in the
manifest under ``nodes[unique_id].depends_on.nodes``. The first
``model.*`` unique_id in that list is the natural parent; that's what
the ``parent_model`` column carries so the page can group tests by the
model they cover.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import UTC, datetime
import json
from pathlib import Path
from typing import TYPE_CHECKING

import duckdb


if TYPE_CHECKING:
    from cms_api import JsonObject, JsonValue


_TABLE_NAME = "dbt_run_results"


@dataclass(frozen=True)
class RunResultRow:
    """One row destined for the ``dbt_run_results`` warehouse table."""

    unique_id: str
    resource_type: str
    name: str
    parent_model: str | None
    status: str
    execution_time: float
    failures: int | None
    message: str | None
    generated_at: datetime


def _as_object(value: JsonValue) -> JsonObject:
    """Narrow a ``JsonValue`` to ``JsonObject`` or raise."""
    if not isinstance(value, dict):
        msg = f"expected JSON object, got {type(value).__name__}"
        raise TypeError(msg)
    return value


def _as_list(value: JsonValue) -> list[JsonValue]:
    """Narrow a ``JsonValue`` to a list or raise."""
    if not isinstance(value, list):
        msg = f"expected JSON list, got {type(value).__name__}"
        raise TypeError(msg)
    return value


def _load_json(path: Path) -> JsonObject:
    """Read a JSON file and assert it decoded to an object."""
    with path.open(encoding="utf-8") as fp:
        payload: JsonValue = json.load(fp)
    return _as_object(payload)


def _parse_generated_at(metadata: JsonValue) -> datetime:
    """Extract ``metadata.generated_at`` (UTC) from a dbt artifact, or fall back to now."""
    if isinstance(metadata, dict):
        raw = metadata.get("generated_at")
        if isinstance(raw, str):
            # dbt writes ISO-8601 with a trailing ``Z``; fromisoformat only
            # accepts ``Z`` from 3.11 onwards, which is safely below our
            # 3.13 pin, but normalize for defensive symmetry.
            iso = raw.replace("Z", "+00:00")
            parsed = datetime.fromisoformat(iso)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=UTC)
            return parsed.astimezone(UTC)
    return datetime.now(tz=UTC)


def _test_parent_model(unique_id: str, manifest_nodes: JsonObject) -> str | None:
    """Return the first ``model.*`` parent unique_id for a test node, or None."""
    node = manifest_nodes.get(unique_id)
    if not isinstance(node, dict):
        return None
    depends_on = node.get("depends_on")
    if not isinstance(depends_on, dict):
        return None
    parents = depends_on.get("nodes")
    if not isinstance(parents, list):
        return None
    for parent in parents:
        if isinstance(parent, str) and parent.startswith("model."):
            return parent
    return None


def _name_from_unique_id(unique_id: str, result: JsonObject) -> str:
    """Prefer an explicit ``node.name`` on the result; fall back to the last dot-segment."""
    name = result.get("name")
    if isinstance(name, str) and name:
        return name
    return unique_id.rsplit(".", 1)[-1]


def _coerce_failures(raw: JsonValue) -> int | None:
    """Coerce dbt's ``failures`` field (int | null | occasionally missing) to int|None."""
    if raw is None:
        return None
    if isinstance(raw, bool):
        # bool is a subclass of int; dbt never emits bool here, but be safe.
        return int(raw)
    if isinstance(raw, int):
        return raw
    return None


def _coerce_execution_time(raw: JsonValue) -> float:
    """Coerce ``execution_time`` (float per dbt schema) to float, defaulting to 0.0."""
    if isinstance(raw, bool):
        return float(int(raw))
    if isinstance(raw, (int, float)):
        return float(raw)
    return 0.0


def _coerce_message(raw: JsonValue) -> str | None:
    """Coerce ``message`` (str | null) to str|None."""
    if isinstance(raw, str):
        return raw
    return None


def build_rows(run_results: JsonObject, manifest: JsonObject) -> list[RunResultRow]:
    """Convert a dbt ``run_results.json`` payload into row dataclasses."""
    generated_at = _parse_generated_at(run_results.get("metadata"))
    results = _as_list(run_results.get("results", []))
    manifest_nodes_raw = manifest.get("nodes", {})
    manifest_nodes = manifest_nodes_raw if isinstance(manifest_nodes_raw, dict) else {}

    rows: list[RunResultRow] = []
    for entry in results:
        result = _as_object(entry)
        unique_id_raw = result.get("unique_id")
        if not isinstance(unique_id_raw, str) or not unique_id_raw:
            continue
        resource_type = unique_id_raw.split(".", 1)[0]
        parent_model = _test_parent_model(unique_id_raw, manifest_nodes) if resource_type in {"test", "unit_test"} else None
        status_raw = result.get("status")
        status = status_raw if isinstance(status_raw, str) else ""
        rows.append(
            RunResultRow(
                unique_id=unique_id_raw,
                resource_type=resource_type,
                name=_name_from_unique_id(unique_id_raw, result),
                parent_model=parent_model,
                status=status,
                execution_time=_coerce_execution_time(result.get("execution_time")),
                failures=_coerce_failures(result.get("failures")),
                message=_coerce_message(result.get("message")),
                generated_at=generated_at,
            )
        )
    return rows


def write_table(rows: list[RunResultRow], warehouse: Path) -> None:
    """Create/replace ``dbt_run_results`` in the DuckDB warehouse at ``warehouse``."""
    con = duckdb.connect(str(warehouse))
    try:
        con.execute(
            f"""
            CREATE OR REPLACE TABLE {_TABLE_NAME} (
                unique_id VARCHAR,
                resource_type VARCHAR,
                name VARCHAR,
                parent_model VARCHAR,
                status VARCHAR,
                execution_time DOUBLE,
                failures BIGINT,
                message VARCHAR,
                generated_at TIMESTAMPTZ
            )
            """
        )
        if rows:
            payload = [
                (
                    r.unique_id,
                    r.resource_type,
                    r.name,
                    r.parent_model,
                    r.status,
                    r.execution_time,
                    r.failures,
                    r.message,
                    r.generated_at,
                )
                for r in rows
            ]
            con.executemany(
                f"""
                INSERT INTO {_TABLE_NAME}
                (unique_id, resource_type, name, parent_model, status,
                 execution_time, failures, message, generated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,  # noqa: S608  # _TABLE_NAME is a module-level constant, not user input
                payload,
            )
    finally:
        con.close()


def publish(run_results_path: Path, manifest_path: Path, warehouse: Path) -> int:
    """Read artifacts, project rows, and write them to the warehouse. Returns row count."""
    run_results = _load_json(run_results_path)
    manifest = _load_json(manifest_path)
    rows = build_rows(run_results, manifest)
    if not rows:
        msg = f"no results found in {run_results_path} — refusing to publish an empty {_TABLE_NAME} table"
        raise ValueError(msg)
    write_table(rows, warehouse)
    return len(rows)


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint: parse args, run ``publish``, print a one-line summary."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--run-results", required=True, type=Path, help="Path to dbt run_results.json")
    parser.add_argument("--manifest", required=True, type=Path, help="Path to dbt manifest.json")
    parser.add_argument("--warehouse", required=True, type=Path, help="Path to the DuckDB warehouse file")
    args = parser.parse_args(argv)

    n = publish(args.run_results, args.manifest, args.warehouse)
    print(f"wrote {n} rows to {_TABLE_NAME} in {args.warehouse}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
