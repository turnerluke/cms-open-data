-- State-level HRRP view. Inner join on `dim_hospital` for the state
-- column drops ~20 CCNs that don't reconcile with the Care Compare
-- hospital roster.
select
    h.state,
    count(distinct r.ccn) as hospitals,
    count(r.excess_readmission_ratio) as measured_rows,
    avg(r.excess_readmission_ratio) as avg_err,
    count(case when r.is_penalized then 1 end) as penalized_rows,
    count(case when r.is_penalized then 1 end) / cast(
        nullif(count(r.excess_readmission_ratio), 0) as double
    ) as penalized_share
from main_marts.fct_hospital_readmissions as r
inner join main_marts.dim_hospital as h on r.ccn = h.ccn
where h.state is not null
group by 1
order by hospitals desc
