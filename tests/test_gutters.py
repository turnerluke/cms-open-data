"""Validate that visual gutter lines are exactly 128 characters wide.

A "gutter" is a comment line that's nothing but the comment marker plus
`=` characters, used as a section separator in config and source files.
This repo standardizes on **128-column gutters** across all comment styles
(`#`, `//`, `--`) and indentation depths. Every gutter line — including
indented ones nested inside YAML keys, JS objects, etc. — must be exactly
128 columns wide.
"""

from __future__ import annotations

from pathlib import Path
import re
import subprocess

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
TARGET_WIDTH = 128

# Match: leading whitespace, a single comment marker (#, //, --), one space
# (or tab), then nothing but `=` characters to end-of-line.
GUTTER_RE = re.compile(r"^(?P<prefix>\s*(?:#|//|--)\s)=+\s*$")

# Suffixes we don't want to read as text (binary, lockfiles, generated).
BINARY_SUFFIXES = frozenset(
    {
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".ico",
        ".webp",
        ".svg",
        ".woff",
        ".woff2",
        ".ttf",
        ".eot",
        ".pdf",
        ".zip",
        ".tar",
        ".gz",
        ".lock",
    }
)


def _tracked_text_files() -> list[Path]:
    """Return all git-tracked files in the repo, filtering out binaries."""
    result = subprocess.run(
        ["git", "ls-files"],  # noqa: S607
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [
        REPO_ROOT / rel
        for rel in result.stdout.splitlines()
        if rel and (REPO_ROOT / rel).is_file() and (REPO_ROOT / rel).suffix not in BINARY_SUFFIXES
    ]


@pytest.mark.parametrize(
    "path",
    _tracked_text_files(),
    ids=lambda p: str(p.relative_to(REPO_ROOT)),
)
def test_gutters_are_128_chars(path: Path) -> None:
    """Every gutter line in the file must be exactly 128 columns wide."""
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        pytest.skip(f"non-utf8 file: {path}")

    violations: list[str] = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        if GUTTER_RE.match(line) and len(line) != TARGET_WIDTH:
            violations.append(f"  line {lineno}: width={len(line)} (expected {TARGET_WIDTH}): {line!r}")

    assert not violations, f"\n{path.relative_to(REPO_ROOT)} has gutter lines not at {TARGET_WIDTH} cols:\n" + "\n".join(
        violations
    )
