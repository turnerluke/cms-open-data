-- Share of dialysis facilities offering each service line.
select 'In-center hemodialysis' as service, count(*) filter (
        where offers_incenter_hemodialysis
    ) as facilities
from main_marts.dim_dialysis_facility
union all
select 'Peritoneal dialysis', count(*) filter (
    where offers_peritoneal_dialysis
) from main_marts.dim_dialysis_facility
union all
select 'Home hemodialysis training', count(*) filter (
    where offers_home_hemodialysis_training
) from main_marts.dim_dialysis_facility
union all
select 'Late shift', count(*) filter (where offers_late_shift)
from main_marts.dim_dialysis_facility
order by facilities desc
