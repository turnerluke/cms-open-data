-- Dialysis five-star rating distribution. Unrated facilities are
-- surfaced as a "(Unrated)" bucket so the totals reconcile to the
-- facility count.
select
    case
        when five_star is null then '(Unrated)'
        else cast(five_star as varchar)
    end as star_rating,
    case when five_star is null then 6 else five_star end as sort_order,
    count(*) as facilities
from main_marts.dim_dialysis_facility
group by 1, 2
order by sort_order
