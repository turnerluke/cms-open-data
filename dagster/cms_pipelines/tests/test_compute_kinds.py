"""Guard rail: every asset's `compute_kind` / `kinds` value must be canonical.

Dagster's UI only renders an icon for kind labels that exist in its built-in
``KNOWN_TAGS`` map. Any string is *accepted* at definition time, so it's easy
to pass a name like ``"cms_api"`` that has no icon and conveys nothing in the
UI. This test makes those mistakes fail in CI rather than land silently.

The allowlist is intentionally a small, project-specific subset of the
roughly 245 kinds Dagster ships icons for. Pick from that subset; add new
entries only after confirming the kind exists upstream.

If a future agent needs to add a new kind:

1. Confirm the label exists in Dagster's canonical source:
   https://github.com/dagster-io/dagster/blob/master/js_modules/ui-core/src/graph/OpTags.tsx
   (search for ``export const KNOWN_TAGS``; every top-level key in that record
   is a valid label).
2. Add the label to ``_ALLOWED_KINDS`` below, with a one-line rationale
   pointing at the asset group it covers.
3. If a label *isn't* in ``KNOWN_TAGS``, request an icon at
   https://github.com/dagster-io/dagster/issues — don't sneak it in here.

The test also catches the inverse mistake: using ``compute_kind`` (legacy
singular) when ``kinds`` (modern plural) would be more idiomatic for assets
that span multiple technologies. Both kwargs are checked.
"""

from cms_pipelines.definitions import defs


# Project-scoped allowlist. Every entry MUST appear in Dagster's KNOWN_TAGS
# (see module docstring for the source link).
_ALLOWED_KINDS: frozenset[str] = frozenset(
    {
        "python",  # cms_* extraction assets — pure Python compute + httpx
        "dbt",  # dbt-managed staging/intermediate/marts models
        "duckdb",  # dbt target adapter; surfaces alongside `dbt` on dbt assets
    },
)

_KNOWN_TAGS_URL = "https://github.com/dagster-io/dagster/blob/master/js_modules/ui-core/src/graph/OpTags.tsx"
_LEGACY_COMPUTE_KIND_TAG = "dagster/compute_kind"


def _asset_kinds(asset_def: object) -> tuple[str, set[str]]:
    """Return ``(asset_key_str, {every kind label set on this asset})``.

    Combines the modern ``AssetSpec.kinds`` (set, per-spec) and the legacy
    ``compute_kind`` kwarg (single string, stored on ``op.tags`` under
    ``dagster/compute_kind``). Either or both may be unset.
    """
    kinds: set[str] = set()
    spec_keys: list[str] = []
    for spec in asset_def.specs:  # type: ignore[attr-defined]
        spec_keys.append(spec.key.to_user_string())
        kinds.update(spec.kinds)
    op = getattr(asset_def, "op", None)
    if op is not None and op.tags:
        legacy = op.tags.get(_LEGACY_COMPUTE_KIND_TAG)
        if legacy:
            kinds.add(legacy)
    label = ",".join(spec_keys) if spec_keys else repr(asset_def)
    return label, kinds


def test_every_asset_uses_a_canonical_kind() -> None:
    """Reject any asset whose `compute_kind`/`kinds` isn't in `_ALLOWED_KINDS`.

    The failure message lists each offending asset alongside the value it
    used, the project allowlist, and the canonical Dagster source so a
    future contributor (or agent) can resolve the mistake in one step.
    """
    violations: list[str] = []
    for asset_def in defs().assets:
        if not hasattr(asset_def, "specs"):
            continue
        label, kinds = _asset_kinds(asset_def)
        if not kinds:
            violations.append(
                f"  - {label}: no `compute_kind`/`kinds` set. Pick one from the project allowlist.",
            )
            continue
        bad = kinds - _ALLOWED_KINDS
        if bad:
            violations.append(f"  - {label}: uses {sorted(bad)!r}, which is not in the project allowlist.")

    if violations:
        msg = (
            "One or more Dagster assets are using a `compute_kind` / `kinds` "
            "value that this project doesn't allow.\n\n"
            f"Project allowlist: {sorted(_ALLOWED_KINDS)}\n\n"
            "Offending assets:\n" + "\n".join(violations) + "\n\n"
            "How to fix:\n"
            '  1. If the asset is plain Python compute, use `compute_kind="python"`.\n'
            '  2. For dbt-managed assets, the `DbtProjectComponent` sets `kinds={"dbt", "duckdb"}`\n'
            "     automatically — don't override.\n"
            "  3. To introduce a NEW kind label, first confirm it exists in Dagster's canonical\n"
            f"     KNOWN_TAGS map: {_KNOWN_TAGS_URL}\n"
            "     (search for `export const KNOWN_TAGS`). Each top-level key is a valid label.\n"
            "  4. Only then add the label to `_ALLOWED_KINDS` in this test module with a\n"
            "     one-line rationale.\n"
            "  5. If the label you want isn't in `KNOWN_TAGS`, request an icon upstream at\n"
            "     https://github.com/dagster-io/dagster/issues rather than smuggling it in.\n"
        )
        raise AssertionError(msg)
