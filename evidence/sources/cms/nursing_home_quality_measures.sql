select
    measure_source,
    measure_code,
    any_value(measure_name) as measure_name,
    any_value(resident_type) as resident_type,
    bool_or(used_in_five_star_rating) as used_in_five_star_rating,
    count(*) as facility_rows,
    count(score) as facilities_reporting,
    avg(score) as avg_score,
    median(score) as median_score
from main_marts.fct_nursing_home_quality
group by 1, 2
order by measure_source, resident_type, measure_code
