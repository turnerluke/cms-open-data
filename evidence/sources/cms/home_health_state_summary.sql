select
    state,
    count(*) as agencies,
    count(quality_of_patient_care_star_rating) as rated_agencies,
    avg(quality_of_patient_care_star_rating) as avg_star_rating
from main_marts.dim_home_health_agency
group by state
order by agencies desc
