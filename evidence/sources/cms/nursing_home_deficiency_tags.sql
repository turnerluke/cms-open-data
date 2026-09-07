select
    deficiency_prefix || deficiency_tag as deficiency_tag,
    any_value(deficiency_description) as deficiency_description,
    count(*) as citations,
    count(distinct ccn) as facilities_cited,
    cast(
        count(case when is_complaint_deficiency then 1 end) as double
    ) / count(*) as complaint_share
from main_marts.fct_nursing_home_enforcement
where action_type = 'deficiency'
group by 1
order by citations desc
limit 25
