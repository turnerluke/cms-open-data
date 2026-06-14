# No `typing.Any`

`typing.Any` is banned in this repo — in both production code and tests.

## Why

`Any` silently disables the type checker for any value it taints, and the
taint propagates through every caller that reads the annotation. A function
returning `Any` makes all of its callers `Any`-shaped at the point of use,
which defeats the purpose of running a type checker at all.

`object` and `Mapping[str, object]` are **not** acceptable substitutes —
they advertise no more shape information than `Any` and force callers to
`isinstance`-check before doing anything useful.

## What to use instead

- **Known shape:** model it precisely with `TypedDict`, a Pydantic
  `BaseModel`, or a `dataclass`. Callers get autocomplete and the type
  checker can verify field access.
- **JSON-shaped data of unknown nesting:** use the `JsonValue` /
  `JsonObject` aliases re-exported from `cms_api`. They are PEP 695 type
  aliases for the recursive union of anything that round-trips through
  `json.loads` / `json.dumps`. Unlike `Any` they are a true union, so
  narrowing with `isinstance` works as expected:

    ```python
    from cms_api import JsonObject, JsonValue

    def parse(payload: JsonValue) -> JsonObject:
        if not isinstance(payload, dict):
            raise TypeError("expected JSON object")
        return payload  # mypy: dict[str, JsonValue], i.e. JsonObject
    ```

- **Decorator that genuinely loses the inner type** (e.g. `tenacity.retry`
  widens its return to `Any`): rebind through a typed local at the
  boundary so the precise type propagates out.

    ```python
    result: JsonValue = _do()
    return result
    ```

    Do **not** use `typing.cast` — it laundering-casts through `Any` and
    defeats the same checker the alias was supposed to satisfy.

## How it's enforced

- **Ruff `ANN401`** rejects `Any` in function annotations. Enabled
  repo-wide via `select = ["ALL"]` in `ruff.toml`.
- **Ruff `flake8-tidy-imports.banned-api`** rejects `from typing import
Any` and `typing.Any` references at the import site. Configured in
  `ruff.toml` under `[lint.flake8-tidy-imports.banned-api]`.
- These rules apply equally to `tests/` — the per-file-ignores in
  `ruff.toml` deliberately do **not** include `ANN401` or `TID251`.
- The Stop hook runs `pre-commit run --all-files`, which runs ruff, so
  any agent turn that reintroduces `Any` fails before it can end.
