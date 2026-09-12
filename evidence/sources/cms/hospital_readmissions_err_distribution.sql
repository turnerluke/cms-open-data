-- ERR distribution binned to 0.02-wide buckets for a per-condition
-- histogram. Only measured rows are counted.
select
    condition,
    round(floor(excess_readmission_ratio / 0.02) * 0.02, 2) as err_bin,
    count(*) as hospitals
from main_marts.fct_hospital_readmissions
where excess_readmission_ratio is not null
group by 1, 2
order by 1, 2
