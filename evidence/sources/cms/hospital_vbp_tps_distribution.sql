-- TPS distribution binned to 5-point buckets. `total_performance_score`
-- is not-null across all VBP rows in the FY2026 vintage.
select
    cast(floor(total_performance_score / 5) * 5 as integer) as tps_bin,
    count(*) as hospitals
from main_marts.fct_hospital_vbp
group by 1
order by 1
