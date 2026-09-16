-- Top 15 models by build-time execution seconds. Useful for spotting
-- expensive nodes and regressions week over week.
select
    name as model,
    status,
    execution_time
from dbt_run_results
where resource_type = 'model'
order by execution_time desc
limit 15
