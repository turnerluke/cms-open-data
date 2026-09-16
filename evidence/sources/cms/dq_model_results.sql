-- Per-model view: model status + execution time plus a rollup of the
-- tests attributed to that model (via ``dbt_run_results.parent_model``).
with models as (
    select
        unique_id,
        name,
        status,
        execution_time
    from dbt_run_results
    where resource_type = 'model'
),
tests as (
    select
        parent_model,
        count(*) as tests_total,
        count(*) filter (where status in ('success', 'pass'))
            as tests_passed,
        count(*) filter (where status = 'warn') as tests_warned,
        count(*) filter (where status in ('fail', 'error'))
            as tests_failed
    from dbt_run_results
    where resource_type = 'test'
      and parent_model is not null
    group by parent_model
)
select
    m.name as model,
    m.status as model_status,
    m.execution_time as execution_time,
    coalesce(t.tests_total, 0) as tests_total,
    coalesce(t.tests_passed, 0) as tests_passed,
    coalesce(t.tests_warned, 0) as tests_warned,
    coalesce(t.tests_failed, 0) as tests_failed
from models m
left join tests t on t.parent_model = m.unique_id
order by tests_warned desc, tests_failed desc, m.name
