-- Test / model outcome rollup by resource type + status, plus a
-- sentinel row (resource_type 'models_without_tests', status 'info')
-- counting models with zero attributed tests. The page renders the
-- whole result as one table and explains the sentinel row in prose.
with rollup as (
    select
        resource_type,
        status,
        count(*) as nodes
    from dbt_run_results
    group by resource_type, status
),
uncovered as (
    select
        'models_without_tests' as resource_type,
        'info' as status,
        count(*) as nodes
    from dbt_run_results m
    where m.resource_type = 'model'
      and not exists (
          select 1
          from dbt_run_results t
          where t.resource_type = 'test'
            and t.parent_model = m.unique_id
      )
)
select resource_type, status, nodes
from rollup
union all
select resource_type, status, nodes
from uncovered
order by resource_type, status
