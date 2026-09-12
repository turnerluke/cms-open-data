select
    condition,
    count(excess_readmission_ratio) as hospitals_measured,
    avg(excess_readmission_ratio) as avg_err,
    median(excess_readmission_ratio) as median_err,
    min(excess_readmission_ratio) as min_err,
    max(excess_readmission_ratio) as max_err,
    count(case when is_penalized then 1 end) as penalized_hospitals,
    count(case when is_penalized then 1 end) / cast(
        nullif(count(excess_readmission_ratio), 0) as double
    ) as penalized_share
from main_marts.fct_hospital_readmissions
group by 1
order by 1
