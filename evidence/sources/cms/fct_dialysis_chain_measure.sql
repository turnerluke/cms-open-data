-- Chain-group x measure_code rollup of fct_dialysis_quality. Grain:
-- (chain_group, measure_code). See dbt model
-- `fct_dialysis_chain_measure` for the aggregation semantics (reported
-- only, unweighted vs denominator-weighted means, category counts on
-- the standardized-ratio family).
select
    chain_group,
    measure_code,
    measure_name,
    denominator_unit,
    n_facilities_total,
    n_facilities_reported,
    score_unweighted_mean,
    score_weighted_mean,
    total_denominator,
    n_better_than_expected,
    n_as_expected,
    n_worse_than_expected,
    n_not_available,
    as_of
from main_marts.fct_dialysis_chain_measure
