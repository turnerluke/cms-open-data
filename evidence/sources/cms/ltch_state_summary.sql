-- LTCH footprint by state with total bed capacity.
select
    state,
    count(*) as facilities,
    sum(total_number_of_beds) as total_beds
from main_marts.dim_ltch
group by 1
order by facilities desc
