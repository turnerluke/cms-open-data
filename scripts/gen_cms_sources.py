"""Render `_cms__sources.yml` from the dataset registry.

The dbt sources file is a pure projection of `libs/cms_api/datasets.toml`:
one `- name: cms_<key>` block per registry row, with the row's
`description` flowed into a YAML literal-block scalar. The header
(``name: cms_raw`` + ``external_location`` meta) is fixed and identical
across every emit.

A few Dagster `cms_*` assets bypass the registry (custom config or sweep
shape that the source-type rules don't cover yet). Those live in
``_EXTRA_SOURCES`` below so the dbt sources file still lists every
asset that lands Parquet under ``data/raw/``.

Run with ``--write`` to overwrite the dbt sources file; default is
stdout so the sync test under `tests/` can diff against the on-disk
copy without touching it.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import textwrap
from typing import TYPE_CHECKING

from cms_api import DatasetSpec, load_registry


if TYPE_CHECKING:
    from collections.abc import Iterable


# Repo root -> this file's parent dir's parent dir.
_REPO_ROOT = Path(__file__).resolve().parents[1]
_SOURCES_YML = _REPO_ROOT / "dbt" / "cms_analytics" / "models" / "staging" / "cms" / "_cms__sources.yml"


# Indent at which `- name:` lines for tables sit. The corresponding
# `description: |` lives two more spaces in, and the description content
# itself another two — i.e. ten spaces total.
_TABLE_INDENT = " " * 6
_FIELD_INDENT = " " * 8
_CONTENT_INDENT = " " * 10
_WRAP_WIDTH = 65

_HEADER = """\
version: 2

sources:
  - name: cms_raw
    description: |
      Raw Parquet landed by the Dagster `cms_pipelines` project into
      `data/raw/`. dbt reads these files in place via DuckDB's
      `external_location`; nothing is re-materialized at this layer.
    meta:
      external_location: "{{ env_var('CMS_RAW_ROOT', '../../data/raw') }}/{name}/*.parquet"
    tables:
"""

# Hand-written Dagster assets not driven by `datasets.toml`. Each entry
# is ``(cms_<key>, description)``. Inserted in registry order between
# the matching siblings; see ``_assemble_table_blocks`` for how the
# position is chosen. TODO: collapse these into the registry once
# `DatasetSpec` grows a source type that fits their config shape.
_EXTRA_SOURCES: tuple[tuple[str, str, str], ...] = (
    # name, description, after_key (insert immediately after this registry key)
    (
        "cms_nppes_providers",
        (
            "NPPES organizational providers (NPI-2), swept state-by-state "
            "from the NPI Registry by the `cms_nppes_providers` Dagster "
            "asset. Not exhaustive: NPPES caps any single query at 1,200 "
            "reachable rows."
        ),
        "healthcare_gov_articles",
    ),
)


def _render_block(name: str, description: str) -> str:
    """Emit one ``- name: <name>`` block with a literal-scalar description."""
    wrapped = textwrap.fill(
        description,
        width=_WRAP_WIDTH,
        break_long_words=False,
        break_on_hyphens=False,
    )
    body = "\n".join(f"{_CONTENT_INDENT}{line}" for line in wrapped.splitlines())
    return f"{_TABLE_INDENT}- name: {name}\n{_FIELD_INDENT}description: |\n{body}\n"


def _assemble_table_blocks(specs: Iterable[DatasetSpec]) -> str:
    """Interleave registry rows and ``_EXTRA_SOURCES`` in file order."""
    extras_by_after = {after_key: (name, desc) for name, desc, after_key in _EXTRA_SOURCES}
    out: list[str] = []
    for spec in specs:
        out.append(_render_block(f"cms_{spec.key}", spec.description))
        extra = extras_by_after.pop(spec.key, None)
        if extra is not None:
            name, desc = extra
            out.append(_render_block(name, desc))
    if extras_by_after:
        unmatched = ", ".join(extras_by_after)
        msg = f"_EXTRA_SOURCES references unknown registry keys: {unmatched}"
        raise ValueError(msg)
    return "".join(out)


def render(specs: list[DatasetSpec]) -> str:
    """Render the full `_cms__sources.yml` body for ``specs``."""
    return _HEADER + _assemble_table_blocks(specs)


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint: write to ``--write`` path or print to stdout."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--write",
        action="store_true",
        help=f"Overwrite {_SOURCES_YML.relative_to(_REPO_ROOT)} in place.",
    )
    args = parser.parse_args(argv)

    rendered = render(load_registry())
    if args.write:
        _SOURCES_YML.write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
