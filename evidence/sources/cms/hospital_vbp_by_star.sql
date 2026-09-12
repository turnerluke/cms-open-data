-- TPS by overall Care Compare star rating. Inner join drops the ~9
-- VBP hospitals whose CCN doesn't reconcile with `dim_hospital`, and
-- the `where` filters out hospitals that CMS didn't publish a star
-- rating for.
select
    h.hospital_overall_rating as stars,
    count(*) as hospitals,
    avg(v.total_performance_score) as avg_tps,
    median(v.total_performance_score) as median_tps
from main_marts.fct_hospital_vbp as v
inner join main_marts.dim_hospital as h on v.ccn = h.ccn
where h.hospital_overall_rating is not null
group by 1
order by 1
