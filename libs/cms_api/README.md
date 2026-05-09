# cms-api

Sync Python client library for CMS public APIs. Lives inside the
`cms-open-data` monorepo at `libs/cms_api/` and is consumed as a uv workspace
member by the root project.

## Scope

This library does one thing: fetch data from CMS public APIs and return
typed records. No transformation, no caching, no orchestration — those live
downstream in pipeline code.

Sources:

| Source                         | Module                                            | Auth                       |
| ------------------------------ | ------------------------------------------------- | -------------------------- |
| `data.cms.gov` (Socrata)       | `cms_api.socrata`                                 | Optional Socrata app token |
| `data.medicaid.gov` (Socrata)  | `cms_api.socrata` (pass `domain=MEDICAID_DOMAIN`) | Optional Socrata app token |
| `www.healthcare.gov` (content) | `cms_api.healthcare_gov`                          | None                       |
| NPPES NPI Registry             | `cms_api.nppes`                                   | None                       |

The Marketplace **plan-finder** API and the hospital MRF / bulk-file
downloads are out of scope and will be handled separately.

## Install

The library is a uv workspace member of `cms-open-data`. From the repo root:

```bash
uv sync
```

`from cms_api import ...` is then available everywhere in the workspace.

## Usage

```python
from cms_api import iter_part_d_spending_by_drug, get_provider_by_npi

# Stream every row of Medicare Part D Spending by Drug
for drug in iter_part_d_spending_by_drug():
    print(drug.brnd_name, drug.gnrc_name)

# Look up a provider
provider = get_provider_by_npi("1234567893")
if provider:
    print(provider.basic.last_name if provider.basic else "?")
```

For an arbitrary Socrata dataset (CMS or Medicaid):

```python
from cms_api import iter_dataset, MEDICAID_DOMAIN

for row in iter_dataset("abcd-efgh", domain=MEDICAID_DOMAIN, where="state = 'CA'"):
    ...
```

## Configuration

All defaults can be overridden via environment variables:

| Variable                        | Default | Purpose                                                    |
| ------------------------------- | ------- | ---------------------------------------------------------- |
| `CMS_API_SOCRATA_APP_TOKEN`     | unset   | Socrata app token for `data.cms.gov` / `data.medicaid.gov` |
| `CMS_API_TIMEOUT`               | `30`    | HTTP request timeout (seconds)                             |
| `CMS_API_RETRY_MAX_ATTEMPTS`    | `5`     | Total tries (including the first) for retryable errors     |
| `CMS_API_RETRY_WAIT_MULTIPLIER` | `0.5`   | Exponential-backoff multiplier (seconds)                   |

Retries fire on transport errors and HTTP 429 / 5xx; client-side 4xx surface
immediately.

## Adding a new endpoint

1. Identify the dataset/resource and any auth.
2. Declare a Pydantic model with `model_config = ConfigDict(extra="allow")`
   and only the fields you've committed to. Year-suffixed columns and
   schema-drift-prone fields belong in the untyped extras.
3. Add a typed wrapper that calls the existing `iter_dataset` /
   `request_json` helper — don't reach for new HTTP plumbing.
4. Write at least: a happy-path test, a pagination test (where applicable),
   and a transient-failure retry test using `respx`.
5. Re-export from `cms_api/__init__.py`.

## Testing

```bash
cd libs/cms_api
uv run pytest
uv run mypy
```

Tests use [`respx`](https://github.com/lundberg/respx) — no real network
calls. The retry wait multiplier is set to `0` in the test fixture so retry
tests run instantly.
