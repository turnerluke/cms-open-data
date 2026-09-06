"""Backfill vintage sidecars for already-extracted datasets.

Extraction assets write a vintage sidecar on every materialization (see
:mod:`cms_pipelines.defs.cms.vintage_sidecar`), but extracts landed
before vintage tracking existed have none — and ``data/raw/`` is
gitignored, so a fresh checkout that copies raw data in needs a way to
regenerate the sidecars without re-downloading anything. This module
re-fetches just the (tiny) upstream metadata for every registry dataset
that already has Parquet on disk and writes the missing sidecars.

The backfilled ``captured_at`` is the backfill time, not the original
extraction time; the upstream ``modified``/``temporal`` dates still
describe whatever snapshot CMS currently publishes, which for a repo
kept reasonably fresh is the snapshot on disk.

Run from the repo root::

    uv run --package cms-pipelines python -m cms_pipelines.vintage_backfill
"""

from __future__ import annotations

import argparse
from pathlib import Path

from cms_api import load_registry, local_vintage

from cms_pipelines.defs.cms.vintage_sidecar import capture_dataset_vintage, write_vintage_sidecar
from cms_pipelines.defs.resources import resolve_raw_root


def _has_extract(raw_root: Path, asset_name: str) -> bool:
    """Return True when the asset has at least one landed Parquet file."""
    return any((raw_root / asset_name).glob("*.parquet"))


def backfill_vintage_sidecars(raw_root: Path) -> list[str]:
    """Write a vintage sidecar for every extracted dataset under ``raw_root``.

    Registry datasets with no landed Parquet are skipped — a sidecar
    without data would put phantom rows in the warehouse's vintage table.
    The hand-written NPPES sweep (not a registry row) gets a
    capture-time-only sidecar when its extract exists.

    Returns:
        The asset names whose sidecars were written, in registry order.

    """
    written: list[str] = []
    for spec in load_registry():
        asset_name = f"cms_{spec.key}"
        if not _has_extract(raw_root, asset_name):
            continue
        capture_dataset_vintage(spec, raw_root=raw_root, asset_name=asset_name)
        written.append(asset_name)
    if _has_extract(raw_root, "cms_nppes_providers"):
        write_vintage_sidecar(raw_root, "cms_nppes_providers", local_vintage("nppes_providers", "nppes"))
        written.append("cms_nppes_providers")
    return written


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint: backfill sidecars under ``--raw-root`` (default ``data/raw/``)."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--raw-root",
        type=Path,
        default=Path(resolve_raw_root()),
        help="Raw-data root holding the per-asset Parquet directories.",
    )
    args = parser.parse_args(argv)

    written = backfill_vintage_sidecars(args.raw_root)
    for asset_name in written:
        print(asset_name)  # noqa: T201 -- CLI progress output
    print(f"backfilled {len(written)} vintage sidecar(s)")  # noqa: T201 -- CLI summary
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
