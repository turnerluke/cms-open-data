-- LTCH ownership mix with bed capacity roll-up.
select
    ownership_type,
    count(*) as facilities,
    count(total_number_of_beds) as facilities_with_beds,
    sum(total_number_of_beds) as total_beds,
    avg(total_number_of_beds::double) as avg_beds
from main_marts.dim_ltch
group by 1
order by facilities desc
