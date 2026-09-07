-- CAHPS Hospice composite box-scores. Each caregiver-experience
-- topic (communication, timely help, respect, symptoms, emotional
-- support, overall rating, willingness to recommend) publishes a
-- Bottom / Middle / Top-Box (BBV/MBV/TBV) percentage. Only the
-- `_TBV` (top box) rows below — the most-favorable response — with
-- their national benchmark alongside for context.
--
-- All seven topics have a `_TBV` national benchmark (the national
-- file publishes `Not Applicable` only for the mid-box
-- `EMO_REL_MBV`, which is not used here).
select
    measure_code,
    any_value(measure_name) as measure_name,
    count(score_numeric) as hospices_reporting,
    avg(score_numeric) as avg_score,
    any_value(national_value) as national_value
from main_marts.fct_hospice_cahps
where
    measure_code like '%\_TBV' escape '\'
group by measure_code
order by avg_score desc
