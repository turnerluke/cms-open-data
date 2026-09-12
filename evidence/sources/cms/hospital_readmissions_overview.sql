select
    count(*) as rows_total,
    count(distinct ccn) as hospitals,
    count(distinct condition) as conditions,
    count(excess_readmission_ratio) as measured_rows,
    count(case when is_penalized then 1 end) as penalized_rows,
    count(case when is_penalized then 1 end) / cast(
        nullif(count(excess_readmission_ratio), 0) as double
    ) as penalized_share,
    max(period_start_date) as period_start,
    max(period_end_date) as period_end,
    max(as_of) as as_of
from main_marts.fct_hospital_readmissions
