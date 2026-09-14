-- Standardized-ratio dialysis measures (SIR/SMR/SHR/SRR/SEDR) — count
-- facilities in each CMS "as expected / better / worse / not
-- available" category. Suppressed rows (is_reported = false, i.e.
-- availability_code <> '001') arrive with the literal category
-- 'Not Available', so the bucket needs no synthesis here.
select
    measure_code,
    measure_name,
    category,
    case category
        when 'Better than Expected' then 1
        when 'As Expected' then 2
        when 'Worse than Expected' then 3
        when 'Not Available' then 4
    end as category_sort,
    count(*) as facilities
from main_marts.fct_dialysis_quality
where measure_code in (
    'smr', 'shr', 'sir', 'srr', 'sedr'
)
group by 1, 2, 3, 4
order by measure_code, category_sort
