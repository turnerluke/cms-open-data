select
    state,
    count(*) as hospices,
    count(distinct ownership_type) as ownership_types_present,
    cast(
        count(case when ownership_type = 'For-Profit' then 1 end) as double
    ) / count(*) as for_profit_share
from main_marts.dim_hospice
group by state
order by hospices desc
