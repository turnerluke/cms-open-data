-- One row per home-health quality measure. `national_value` is the
-- national benchmark CMS publishes alongside the agency-level file,
-- so avg / median aggregate agency scores while `national_value` is
-- passed through as the single benchmark for that measure.
select
    measure_source,
    measure_code,
    any_value(measure_name) as measure_name,
    count(*) as agency_rows,
    count(score) as agencies_reporting,
    avg(score) as avg_score,
    median(score) as median_score,
    any_value(national_value) as national_value
from main_marts.fct_home_health_quality
group by 1, 2
order by measure_source, measure_code
