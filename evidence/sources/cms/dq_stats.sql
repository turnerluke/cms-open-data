-- Headline aggregates over ``dbt_run_results`` for the top-of-page
-- BigValues on the data-quality page. All scalars — one row.
select
    (select count(*) from dbt_run_results where resource_type = 'model')
        as models,
    (select count(*) from dbt_run_results where resource_type = 'test')
        as tests,
    (
        select count(*) from dbt_run_results
        where status in ('success', 'pass')
    ) as passes,
    (select count(*) from dbt_run_results where status = 'warn')
        as warns,
    (
        select count(*) from dbt_run_results
        where status in ('fail', 'error')
    ) as failures,
    (select count(*) from dbt_run_results where status = 'skipped')
        as skipped,
    (select sum(execution_time) from dbt_run_results) as total_seconds,
    (select max(generated_at) from dbt_run_results) as generated_at
