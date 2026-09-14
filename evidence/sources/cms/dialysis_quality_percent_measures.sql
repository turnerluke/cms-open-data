-- Percent-of-patients / percent-of-patient-months dialysis quality
-- measures. Averages weight each reporting facility equally.
select
    measure_code,
    measure_name,
    denominator_unit,
    count(*) filter (where is_reported) as facilities_reporting,
    count(*) as facilities_in_scope,
    avg(score_numeric) filter (where is_reported) as avg_score
from main_marts.fct_dialysis_quality
where measure_code in (
    'adult_hd_ktv',
    'adult_pd_ktv',
    'long_term_catheter',
    'hgb_lt_10',
    'hgb_gt_12',
    'hypercalcemia',
    'hcp_vaccination'
)
group by 1, 2, 3
order by avg_score desc nulls last
