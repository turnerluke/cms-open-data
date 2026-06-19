"""Materialization tests for the QHP Landscape ZIP-XLSX assets.

The download step is monkey-patched to copy a fixture ZIP into the asset's
temp dir, so the rest of the pipeline — extract, ``read_xlsx``, write
Parquet — runs end-to-end against a real (tiny) XLSX without any network
calls. ``CMS_RAW_ROOT`` is overridden so the landed Parquet shows up
under a directory the test owns.
"""

from __future__ import annotations

import shutil
from typing import TYPE_CHECKING
import zipfile

from cms_api import DatasetSpec, load_registry
from cms_pipelines.defs.cms import qhp_zip_assets
from cms_pipelines.defs.resources import CMS_RAW_ROOT_ENV
import duckdb
import pyarrow.parquet as pq

from dagster import AssetsDefinition, materialize

import pytest


if TYPE_CHECKING:
    from pathlib import Path


_QHP_SOURCE = "dkan_healthcare_gov_zip"


def _qhp_spec() -> DatasetSpec:
    """Pick the first QHP registry row for parametrizing the asset tests."""
    specs = [s for s in load_registry() if s.source == _QHP_SOURCE]
    assert specs, f"expected at least one {_QHP_SOURCE} row in datasets.toml"
    return specs[0]


def _qhp_asset(spec: DatasetSpec) -> AssetsDefinition:
    """Look up the generated QHP asset for `spec` by its canonical name."""
    return getattr(qhp_zip_assets, f"cms_{spec.key}")


def _write_qhp_xlsx(
    *,
    dest: Path,
    rows: list[tuple[str, ...]] | None = None,
    header: tuple[str, ...] = ("State Code", "FIPS County Code", "County Name"),
    a1_count: str = "2 displayed records",
) -> None:
    """Write a QHP-shaped XLSX: A1 is a count message, A2 is the header, A3+ data.

    DuckDB's ``COPY TO ... (FORMAT XLSX, HEADER false)`` lets us hand-place
    every row so the fixture mirrors the production layout exactly. We
    pad the count message with empty cells so the row has the same width
    as the header; without padding DuckDB throws when columns disagree.
    """
    data_rows = rows if rows is not None else [("CA", "06001", "Alameda"), ("TX", "48001", "Anderson")]
    width = len(header)
    count_row = (a1_count, *("",) * (width - 1))
    union_select = "\n  UNION ALL\n  ".join(
        ["SELECT " + ", ".join(f"'{cell}' AS c{i}" for i, cell in enumerate(row)) for row in (count_row, header, *data_rows)],
    )
    with duckdb.connect(":memory:") as con:
        con.execute("INSTALL excel; LOAD excel;")
        con.execute(f"COPY ({union_select}) TO '{dest}' (FORMAT XLSX, HEADER false)")


def _zip_xlsx(*, xlsx_path: Path, zip_path: Path, arcname: str | None = None) -> None:
    """Pack ``xlsx_path`` into ``zip_path`` under ``arcname`` (default: filename)."""
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(xlsx_path, arcname=arcname or xlsx_path.name)


def _patch_qhp_inputs(
    monkeypatch: pytest.MonkeyPatch,
    *,
    fixture_zip: Path,
    placeholder_url: str = "https://fake.invalid/qhp.zip",
) -> list[str]:
    """Patch the URL resolver and downloader so the asset uses ``fixture_zip``.

    Returns the list of URLs the resolver hands back, so callers can
    assert the placeholder propagated to the materialization metadata.
    """
    captured: list[str] = []

    def fake_resolver(dataset_id: str, *, base_url: str) -> str:
        captured.append(base_url)
        return placeholder_url

    def fake_download(*, url: str, dest: Path) -> None:
        assert url == placeholder_url
        shutil.copyfile(fixture_zip, dest)

    monkeypatch.setattr(qhp_zip_assets, "get_dkan_dataset_zip_url", fake_resolver)
    monkeypatch.setattr(qhp_zip_assets, "_download_zip", fake_download)
    return captured


def test_qhp_asset_written_for_every_registry_row() -> None:
    """Every dkan_healthcare_gov_zip spec must bind a module attribute."""
    specs = [s for s in load_registry() if s.source == _QHP_SOURCE]
    assert specs, "expected at least one QHP registry row"
    for spec in specs:
        asset_def = _qhp_asset(spec)
        assert isinstance(asset_def, AssetsDefinition)
        assert asset_def.key.path[-1] == f"cms_{spec.key}"


def test_qhp_asset_streams_zip_to_parquet(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """The asset extracts the XLSX, skips the A1 count row, and lands the data rows."""
    xlsx_path = tmp_path / "qhp_fixture.xlsx"
    _write_qhp_xlsx(dest=xlsx_path)
    zip_path = tmp_path / "fixture.zip"
    _zip_xlsx(xlsx_path=xlsx_path, zip_path=zip_path)
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    _patch_qhp_inputs(monkeypatch, fixture_zip=zip_path)

    spec = _qhp_spec()
    asset_def = _qhp_asset(spec)

    result = materialize([asset_def])

    assert result.success
    parquets = list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))
    assert len(parquets) == 1
    table = pq.read_table(parquets[0])
    assert table.num_rows == 2
    # Columns are exactly the header row from A2 — no trailing all-null padding.
    assert table.column_names == ["State Code", "FIPS County Code", "County Name"]


def test_qhp_asset_emits_zip_url_and_row_count_metadata(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """`row_count`, `path`, and `zip_url` metadata are attached to the materialization event."""
    xlsx_path = tmp_path / "qhp_fixture.xlsx"
    _write_qhp_xlsx(dest=xlsx_path)
    zip_path = tmp_path / "fixture.zip"
    _zip_xlsx(xlsx_path=xlsx_path, zip_path=zip_path)
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    placeholder_url = "https://data.healthcare.gov/datafile/py2026/fixture.zip"
    _patch_qhp_inputs(monkeypatch, fixture_zip=zip_path, placeholder_url=placeholder_url)

    spec = _qhp_spec()
    asset_def = _qhp_asset(spec)

    result = materialize([asset_def])
    materializations = result.asset_materializations_for_node(asset_def.node_def.name)
    assert len(materializations) == 1
    metadata = materializations[0].metadata
    assert metadata["row_count"].value == 2
    assert str(metadata["path"].value).endswith(".parquet")
    assert metadata["zip_url"].value == placeholder_url


def test_qhp_asset_refuses_empty_xlsx(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A header-only XLSX (zero data rows) trips the empty-extract guard."""
    xlsx_path = tmp_path / "empty.xlsx"
    _write_qhp_xlsx(dest=xlsx_path, rows=[])
    zip_path = tmp_path / "empty.zip"
    _zip_xlsx(xlsx_path=xlsx_path, zip_path=zip_path)
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    _patch_qhp_inputs(monkeypatch, fixture_zip=zip_path)

    spec = _qhp_spec()
    asset_def = _qhp_asset(spec)

    with pytest.raises(Exception, match="zero rows"):
        materialize([asset_def])

    # Empty Parquet must not be left behind for dbt to glob into.
    assert not list((tmp_path / f"cms_{spec.key}").glob("*.parquet"))


def test_qhp_asset_rejects_zip_without_xlsx(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A ZIP without exactly one XLSX is malformed — surface loudly."""
    zip_path = tmp_path / "no_xlsx.zip"
    with zipfile.ZipFile(zip_path, "w") as archive:
        archive.writestr("readme.txt", "not an excel file")
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    _patch_qhp_inputs(monkeypatch, fixture_zip=zip_path)

    spec = _qhp_spec()
    asset_def = _qhp_asset(spec)

    with pytest.raises(Exception, match=r"expected exactly one \.xlsx"):
        materialize([asset_def])


def test_qhp_asset_rejects_zip_with_multiple_xlsx(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """A multi-XLSX archive is a layout change CMS hasn't shipped — fail loudly."""
    xlsx_a = tmp_path / "a.xlsx"
    xlsx_b = tmp_path / "b.xlsx"
    _write_qhp_xlsx(dest=xlsx_a)
    _write_qhp_xlsx(dest=xlsx_b)
    zip_path = tmp_path / "multi.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(xlsx_a, arcname="a.xlsx")
        archive.write(xlsx_b, arcname="b.xlsx")
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    _patch_qhp_inputs(monkeypatch, fixture_zip=zip_path)

    spec = _qhp_spec()
    asset_def = _qhp_asset(spec)

    with pytest.raises(Exception, match=r"expected exactly one \.xlsx"):
        materialize([asset_def])


def test_qhp_asset_routes_through_healthcare_gov_base_url(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """The resolver is called with HEALTHCARE_GOV_DKAN_BASE_URL, not another DKAN host.

    Without this guard the QHP asset could silently route to the medicaid or
    open-payments DKAN host and 404 against an unrelated metastore.
    """
    xlsx_path = tmp_path / "qhp_fixture.xlsx"
    _write_qhp_xlsx(dest=xlsx_path)
    zip_path = tmp_path / "fixture.zip"
    _zip_xlsx(xlsx_path=xlsx_path, zip_path=zip_path)
    monkeypatch.setenv(CMS_RAW_ROOT_ENV, str(tmp_path))
    captured_base_urls = _patch_qhp_inputs(monkeypatch, fixture_zip=zip_path)

    spec = _qhp_spec()
    asset_def = _qhp_asset(spec)

    materialize([asset_def])

    assert captured_base_urls == [qhp_zip_assets.HEALTHCARE_GOV_DKAN_BASE_URL]


# ---------------------------------------------------------------------------
# Helpers — _excel_column_letter and _sniff_column_width
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("n", "expected"),
    [(1, "A"), (26, "Z"), (27, "AA"), (52, "AZ"), (53, "BA"), (702, "ZZ")],
)
def test_excel_column_letter_round_trip(n: int, expected: str) -> None:
    """The helper covers the 1..702 range used by `_XLSX_MAX_COLUMN_WIDTH`."""
    assert qhp_zip_assets._excel_column_letter(n) == expected


@pytest.mark.parametrize("bad", [0, -1, 703])
def test_excel_column_letter_rejects_out_of_range(bad: int) -> None:
    """Values outside the supported range raise instead of silently truncating."""
    with pytest.raises(ValueError, match="out of supported range"):
        qhp_zip_assets._excel_column_letter(bad)


def test_sniff_column_width_finds_first_null(tmp_path: Path) -> None:
    """The sniffer counts only consecutively-populated header cells.

    Production files have hundreds of trailing empty header cells that
    should not become Parquet columns; the sniffer stops at the first
    null so the data read only asks for real columns.
    """
    xlsx_path = tmp_path / "narrow.xlsx"
    _write_qhp_xlsx(dest=xlsx_path, header=("State Code", "FIPS County Code", "County Name"))
    with duckdb.connect(":memory:") as con:
        con.execute("INSTALL excel; LOAD excel;")
        assert qhp_zip_assets._sniff_column_width(con, xlsx_path) == 3
