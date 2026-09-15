r"""Durable vintage ledger over the per-run sidecars.

Extraction assets write ephemeral vintage sidecars under
``<raw-root>/_vintages/<asset_name>.parquet`` on every run and overwrite
them on the next; ``data/raw/`` is gitignored, so no history survives.
This module folds those sidecars — plus a cheap Parquet-footer summary
of the landed data — into a JSONL ledger that is committed to the repo.
CI can then append one row per dataset per run and produce a durable
timeline of how upstream vintages, row counts, and schemas drift.

One JSONL line per (``run_date``, ``dataset_key``). ``run_date`` is
derived from the sidecar's ``captured_at`` (not wall clock) so a rerun
against the same extract is a stable no-op. Existing lines are never
modified; new lines are appended at end-of-file, sorted by
(``run_date``, ``dataset_key``) within the new batch.

``schema_hash`` rule
--------------------
For a dataset, every Parquet file under
``<raw-root>/<asset_name>/*.parquet`` is opened for its schema only.
Each file's schema contributes its own set of ``name:type`` lines; the
lines from all files are unioned into a single set, sorted, and joined
with ``\n``. The first 12 hex chars of the sha256 of that string are
the schema hash. A rename or type change in any file flips the hash;
files that happen to be schema-identical do not (so partitioning a
dataset across multiple identically-typed files is a no-op).

Run from the repo root::

    uv run --package cms-pipelines python -m cms_pipelines.vintage_ledger \
        append --raw-root data/raw --ledger data/vintages/ledger.jsonl

Or verify a candidate ledger covers every row of a reference::

    python -m cms_pipelines.vintage_ledger verify \
        --ledger data/vintages/ledger.jsonl --superset-of other.jsonl
"""

from __future__ import annotations

import argparse
from datetime import UTC, date, datetime
import hashlib
import json
from pathlib import Path
import sys
from typing import TYPE_CHECKING, NamedTuple

import pyarrow.parquet as pq


if TYPE_CHECKING:
    from collections.abc import Iterable

    from cms_api import JsonObject, JsonValue


LEDGER_VERSION = 1
VINTAGES_DIRNAME = "_vintages"
_SCHEMA_HASH_LEN = 12

# Column order for each emitted JSON object. Stable so committed diffs
# stay minimal when a run adds a new dataset in the middle of the file.
_LEDGER_COLUMNS: tuple[str, ...] = (
    "ledger_version",
    "run_date",
    "captured_at",
    "asset_name",
    "dataset_key",
    "source_family",
    "dataset_id",
    "modified",
    "issued",
    "released",
    "temporal_start",
    "temporal_end",
    "row_count",
    "file_count",
    "total_bytes",
    "schema_hash",
)


def _iso_or_none(value: object) -> str | None:
    """Serialize a date/datetime to ISO string, or return None."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str):
        return value
    msg = f"unexpected date-ish value {value!r} ({type(value).__name__})"
    raise TypeError(msg)


def _run_date_from_captured_at(captured_at: object) -> str:
    """Derive a UTC ``YYYY-MM-DD`` from the sidecar's ``captured_at``.

    Aware values (datetime or ISO string with an offset) are converted
    to UTC before the date is taken; naive values are assumed UTC.
    """
    if isinstance(captured_at, str):
        captured_at = datetime.fromisoformat(captured_at)
    if not isinstance(captured_at, datetime):
        msg = f"captured_at must be datetime or ISO string, got {type(captured_at).__name__}"
        raise TypeError(msg)
    if captured_at.tzinfo is not None:
        captured_at = captured_at.astimezone(UTC)
    return captured_at.date().isoformat()


def _read_sidecar(path: Path) -> JsonObject:
    """Return the one-row sidecar as a plain-Python dict."""
    table = pq.read_table(path)
    rows = table.to_pylist()
    if len(rows) != 1:
        msg = f"sidecar {path} has {len(rows)} rows; expected exactly 1"
        raise ValueError(msg)
    return rows[0]


def _summarize_dataset(dataset_dir: Path) -> _DatasetSummary:
    """Summarize a landed dataset by reading Parquet footers only.

    A sidecar without landed parquet (extract cleaned or never
    persisted) is an inconsistent raw root; fail fast rather than
    record a fabricated empty-dataset row that would poison
    ``row_count_delta`` / ``schema_changed`` downstream.
    """
    files = sorted(p for p in dataset_dir.glob("*.parquet") if p.is_file()) if dataset_dir.is_dir() else []
    if not files:
        msg = f"sidecar exists but no parquet files under {dataset_dir}"
        raise FileNotFoundError(msg)
    row_count = 0
    total_bytes = 0
    schema_lines: set[str] = set()
    for file in files:
        metadata = pq.read_metadata(file)
        row_count += metadata.num_rows
        total_bytes += file.stat().st_size
        schema = pq.read_schema(file)
        for field in schema:
            schema_lines.add(f"{field.name}:{field.type!s}")

    canonical = "\n".join(sorted(schema_lines))
    schema_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:_SCHEMA_HASH_LEN]
    return _DatasetSummary(row_count=row_count, file_count=len(files), total_bytes=total_bytes, schema_hash=schema_hash)


class _DatasetSummary(NamedTuple):
    """Parquet-footer summary of a landed dataset."""

    row_count: int
    file_count: int
    total_bytes: int
    schema_hash: str


def _build_ledger_row(*, asset_name: str, sidecar: JsonObject, summary: _DatasetSummary) -> JsonObject:
    """Assemble one JSONL row from a sidecar dict + summary stats."""
    captured_at_iso = _iso_or_none(sidecar.get("captured_at"))
    if captured_at_iso is None:
        msg = f"sidecar for {asset_name!r} is missing captured_at"
        raise ValueError(msg)
    return {
        "ledger_version": LEDGER_VERSION,
        "run_date": _run_date_from_captured_at(sidecar.get("captured_at")),
        "captured_at": captured_at_iso,
        "asset_name": asset_name,
        "dataset_key": sidecar.get("dataset_key"),
        "source_family": sidecar.get("source_family"),
        "dataset_id": sidecar.get("dataset_id"),
        "modified": _iso_or_none(sidecar.get("modified")),
        "issued": _iso_or_none(sidecar.get("issued")),
        "released": _iso_or_none(sidecar.get("released")),
        "temporal_start": _iso_or_none(sidecar.get("temporal_start")),
        "temporal_end": _iso_or_none(sidecar.get("temporal_end")),
        "row_count": summary.row_count,
        "file_count": summary.file_count,
        "total_bytes": summary.total_bytes,
        "schema_hash": summary.schema_hash,
    }


def _row_key(row: JsonObject) -> tuple[str, str]:
    """Extract the ``(run_date, dataset_key)`` primary key from a row."""
    run_date = row.get("run_date")
    dataset_key = row.get("dataset_key")
    if not isinstance(run_date, str) or not isinstance(dataset_key, str):
        msg = f"ledger row missing run_date/dataset_key: {row!r}"
        raise TypeError(msg)
    return run_date, dataset_key


def _ordered_row(row: JsonObject) -> JsonObject:
    """Return the row with keys reordered to ``_LEDGER_COLUMNS``."""
    return {col: row.get(col) for col in _LEDGER_COLUMNS}


def _serialize_row(row: JsonObject) -> str:
    """One-line compact JSON for the ledger."""
    return json.dumps(_ordered_row(row), separators=(",", ":"), ensure_ascii=False)


def read_ledger(path: Path) -> list[JsonObject]:
    """Load an existing JSONL ledger; return ``[]`` when the file is missing."""
    if not path.exists():
        return []
    rows: list[JsonObject] = []
    with path.open(encoding="utf-8") as f:
        for lineno, raw in enumerate(f, start=1):
            line = raw.strip()
            if not line:
                continue
            parsed: JsonValue = json.loads(line)
            if not isinstance(parsed, dict):
                msg = f"{path}:{lineno}: ledger line is not a JSON object"
                raise TypeError(msg)
            version = parsed.get("ledger_version")
            if isinstance(version, int) and version > LEDGER_VERSION:
                msg = (
                    f"{path}:{lineno}: ledger_version={version} is newer than "
                    f"supported ({LEDGER_VERSION}); rewriting its rows would "
                    "silently drop unknown columns"
                )
                raise ValueError(msg)
            rows.append(parsed)
    return rows


def build_run_rows(raw_root: Path) -> list[JsonObject]:
    """Build one ledger row per sidecar under ``raw_root/_vintages/``."""
    vintages_dir = raw_root / VINTAGES_DIRNAME
    if not vintages_dir.is_dir():
        return []
    rows: list[JsonObject] = []
    for sidecar_path in sorted(vintages_dir.glob("*.parquet")):
        asset_name = sidecar_path.stem
        sidecar = _read_sidecar(sidecar_path)
        summary = _summarize_dataset(raw_root / asset_name)
        rows.append(_build_ledger_row(asset_name=asset_name, sidecar=sidecar, summary=summary))
    return rows


def _ends_with_newline(path: Path) -> bool:
    """Return True when ``path`` is missing, empty, or already ends with a newline."""
    if not path.exists() or path.stat().st_size == 0:
        return True
    with path.open("rb") as rb:
        rb.seek(-1, 2)
        return rb.read(1) == b"\n"


def _write_rows(ledger_path: Path, rows: list[JsonObject]) -> None:
    """Append ``rows`` to ``ledger_path`` as JSONL, guaranteeing line separation."""
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        return
    needs_leading_newline = not _ends_with_newline(ledger_path)
    with ledger_path.open("a", encoding="utf-8") as f:
        if needs_leading_newline:
            f.write("\n")
        for row in rows:
            f.write(_serialize_row(row))
            f.write("\n")


def append_ledger(
    *,
    raw_root: Path,
    ledger_path: Path,
    merge_from: Path | None = None,
) -> tuple[int, int]:
    """Append new (``run_date``, ``dataset_key``) rows to ``ledger_path``.

    Returns ``(added, skipped)``: rows written and rows deduped against
    existing keys. ``merge_from`` (if given) is a second JSONL whose
    rows are unioned in before writing — the existing ledger wins on
    conflict, and rows unique to ``merge_from`` are carried forward.
    When the same key appears in both ``merge_from`` and the fresh
    sidecar sweep, the ``merge_from`` row wins (it is unioned first).
    """
    existing = read_ledger(ledger_path)
    seen: set[tuple[str, str]] = {_row_key(r) for r in existing}
    new_rows: list[JsonObject] = []

    merge_rows = read_ledger(merge_from) if merge_from is not None else []
    for row in merge_rows:
        key = _row_key(row)
        if key not in seen:
            seen.add(key)
            new_rows.append(row)

    skipped = 0
    for row in build_run_rows(raw_root):
        key = _row_key(row)
        if key in seen:
            skipped += 1
            continue
        seen.add(key)
        new_rows.append(row)

    new_rows.sort(key=_row_key)
    _write_rows(ledger_path, new_rows)
    return len(new_rows), skipped


def verify_superset(*, ledger_path: Path, reference_path: Path) -> list[tuple[str, str]]:
    """Return keys present in ``reference_path`` but missing from ``ledger_path``."""
    ledger_keys = {_row_key(r) for r in read_ledger(ledger_path)}
    missing: list[tuple[str, str]] = []
    for row in read_ledger(reference_path):
        key = _row_key(row)
        if key not in ledger_keys:
            missing.append(key)
    return missing


def _cmd_append(args: argparse.Namespace) -> int:
    added, skipped = append_ledger(
        raw_root=args.raw_root,
        ledger_path=args.ledger,
        merge_from=args.merge_from,
    )
    print(f"appended {added} row(s), skipped {skipped} same-key row(s) -> {args.ledger}")  # noqa: T201
    return 0


def _cmd_verify(args: argparse.Namespace) -> int:
    missing = verify_superset(ledger_path=args.ledger, reference_path=args.superset_of)
    if missing:
        for run_date, dataset_key in missing:
            print(f"missing: run_date={run_date} dataset_key={dataset_key}", file=sys.stderr)  # noqa: T201
        print(f"{len(missing)} row(s) in {args.superset_of} not covered by {args.ledger}", file=sys.stderr)  # noqa: T201
        return 1
    print(f"{args.ledger} is a superset of {args.superset_of}")  # noqa: T201
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else "")
    sub = parser.add_subparsers(dest="command", required=True)

    append_p = sub.add_parser("append", help="Append a run's ledger rows.")
    append_p.add_argument("--raw-root", type=Path, required=True, help="Raw-data root holding _vintages/ and asset dirs.")
    append_p.add_argument("--ledger", type=Path, required=True, help="JSONL ledger file to append to (created if absent).")
    append_p.add_argument("--merge-from", type=Path, default=None, help="Second JSONL to union in before writing.")
    append_p.set_defaults(func=_cmd_append)

    verify_p = sub.add_parser("verify", help="Exit nonzero unless --ledger covers every row of --superset-of.")
    verify_p.add_argument("--ledger", type=Path, required=True, help="Candidate ledger asserted to be a superset.")
    verify_p.add_argument("--superset-of", type=Path, required=True, help="Reference ledger whose keys must all be present.")
    verify_p.set_defaults(func=_cmd_verify)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    """CLI entrypoint; dispatches to ``append``/``verify``."""
    parser = _build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
