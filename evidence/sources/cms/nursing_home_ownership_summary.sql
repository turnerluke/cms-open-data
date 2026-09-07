select
    ownership_type,
    count(*) as facilities,
    count(overall_rating) as rated_facilities,
    avg(overall_rating) as avg_overall_rating,
    avg(
        reported_total_nurse_staffing_hours_per_resident_per_day
    ) as avg_nurse_staffing_hours,
    -- source column is a 0-100 percentage; divide so the page can
    -- format it with pct formats
    avg(total_nursing_staff_turnover_pct) / 100 as avg_nursing_staff_turnover,
    count(
        case when special_focus_status is not null then 1 end
    ) as special_focus_facilities
from main_marts.dim_nursing_home
group by 1
order by facilities desc
