"""Render `_cms__sources.yml` from the dataset registry.

The dbt sources file is a pure projection of `libs/cms_api/datasets.toml`:
one `- name: cms_<key>` block per registry row, with the row's
`description` flowed into a YAML literal-block scalar. The header
(``name: cms_raw`` + ``external_location`` meta) is fixed and identical
across every emit.

Hand-written Dagster assets (e.g. the NPPES sweep) live in the registry
too, under ``source = "custom"``; that variant carries no fetch config
but still contributes its name+description here.

Run with ``--write`` to overwrite the dbt sources file; default is
stdout so the sync test under `tests/` can diff against the on-disk
copy without touching it.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import textwrap

from cms_api import DatasetSpec, load_registry


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


def render(specs: list[DatasetSpec]) -> str:
    """Render the full `_cms__sources.yml` body for ``specs``."""
    blocks = "".join(_render_block(f"cms_{spec.key}", spec.description) for spec in specs)
    return _HEADER + blocks


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
