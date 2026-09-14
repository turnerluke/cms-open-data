-- Dialysis facility count and rated-star average by state.
select
    state,
    count(*) as facilities,
    sum(number_of_dialysis_stations) as stations,
    sum(case when is_for_profit then 1 else 0 end)::double
        / nullif(count(*), 0) as for_profit_share,
    sum(case when is_chain_owned then 1 else 0 end)::double
        / nullif(count(*), 0) as chain_share,
    avg(five_star::double) as avg_stars
from main_marts.dim_dialysis_facility
group by 1
order by facilities desc
