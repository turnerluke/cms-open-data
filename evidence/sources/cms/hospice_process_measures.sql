-- Hospice Item Set (HIS) process-of-care measures. Each is a
-- percentage compliance rate on a distinct clinical process. Only
-- the `_OBSERVED` rows are pulled here — the paired `_DENOMINATOR`
-- rows carry case counts, not percentages, and cannot be compared
-- alongside the observed rates. The `H_012_00_OBSERVED` composite
-- Hospice Care Index score is also included (0-10 index, not a
-- percentage — so it lives on its own row separately from the
-- process measures in the site presentation).
select
    measure_code,
    any_value(measure_name) as measure_name,
    count(score_numeric) as hospices_reporting,
    avg(score_numeric) as avg_score
from main_marts.fct_hospice_quality
where measure_code in (
    'H_001_01_OBSERVED',
    'H_002_01_OBSERVED',
    'H_003_01_OBSERVED',
    'H_004_01_OBSERVED',
    'H_005_01_OBSERVED',
    'H_006_01_OBSERVED',
    'H_007_01_OBSERVED',
    'H_008_01_OBSERVED'
)
group by measure_code
order by avg_score desc
