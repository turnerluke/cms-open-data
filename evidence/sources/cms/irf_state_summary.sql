-- IRF footprint by state, with the freestanding-vs-unit decomposition.
select
    state,
    count(*) as facilities,
    sum(case when facility_type = 'Freestanding' then 1 else 0 end)
        as freestanding,
    sum(case when facility_type = 'Hospital unit' then 1 else 0 end)
        as hospital_units
from main_marts.dim_irf
group by 1
order by facilities desc
