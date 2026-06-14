"""Shared type aliases for JSON-shaped payloads.

`JsonValue` and `JsonObject` exist so call sites can describe their data
precisely without reaching for `typing.Any`. They mirror the shape of any
value that round-trips through `json.loads` / `json.dumps`, and they are
true unions — narrowing them with `isinstance` works as expected, unlike
`Any` which silently disables the type checker.
"""

type JsonValue = str | int | float | bool | None | list[JsonValue] | dict[str, JsonValue]
type JsonObject = dict[str, JsonValue]
