-- Hospice Care Index / HIS-derived measures. Every score is a
-- percentage within its own domain; the site restricts to a curated
-- list rather than pivoting the raw 60+ measure_codes.
--
-- The `Care_Provided_*` family reports the average share of care
-- days each hospice delivered in a given setting (home, assisted
-- living, nursing facility, etc.); the shares sum to ~100 across
-- settings for a given hospice.
select
    measure_code,
    any_value(measure_name) as measure_name,
    count(score_numeric) as hospices_reporting,
    avg(score_numeric) as avg_pct_of_days
from main_marts.fct_hospice_quality
where measure_code like 'Care_Provided_%'
group by measure_code
order by avg_pct_of_days desc
