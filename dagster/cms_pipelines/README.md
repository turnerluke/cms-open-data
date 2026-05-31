# cms-pipelines

Dagster orchestration for the `cms-open-data` lakehouse. Lives inside the
`cms-open-data` monorepo at `dagster/cms_pipelines/` and is consumed as a
uv workspace member by the root project.

## Layout

Standard `dg`-scaffolded layout:

```text
dagster/cms_pipelines/
├── pyproject.toml          # workspace member + [tool.dg] config
├── src/cms_pipelines/
│   ├── definitions.py      # entry point; loads everything under defs/
│   └── defs/               # auto-discovered assets, jobs, resources, sensors
└── tests/
```

## Install

From the repo root:

```bash
uv sync --all-packages --all-groups
```

## Develop

From this directory:

```bash
uv run dg list defs       # show what currently loads
uv run dg check defs      # validate components and defs
uv run dg dev             # launch the Dagster UI on port 3000
```

## Add definitions

Scaffold new components, assets, resources, and other defs under
`src/cms_pipelines/defs/` with `uv run dg scaffold ...`. See the
[Dagster `dg` guide](https://docs.dagster.io/guides/labs/dg) for the
component types `dg` ships with.
