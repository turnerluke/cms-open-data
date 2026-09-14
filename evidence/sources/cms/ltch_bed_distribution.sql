-- LTCH bed-count distribution. The `(no bed count)` bucket captures
-- rows where `total_number_of_beds` is null.
select
    case
        when total_number_of_beds is null then '(no bed count)'
        when total_number_of_beds < 25 then 'under 25'
        when total_number_of_beds < 50 then '25–49'
        when total_number_of_beds < 100 then '50–99'
        when total_number_of_beds < 200 then '100–199'
        else '200+'
    end as bed_bucket,
    case
        when total_number_of_beds is null then 7
        when total_number_of_beds < 25 then 1
        when total_number_of_beds < 50 then 2
        when total_number_of_beds < 100 then 3
        when total_number_of_beds < 200 then 4
        else 5
    end as sort_order,
    count(*) as facilities
from main_marts.dim_ltch
group by 1, 2
order by sort_order
