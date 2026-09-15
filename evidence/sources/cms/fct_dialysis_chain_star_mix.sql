-- Facility five-star distribution by chain_group. One row per
-- chain_group (DaVita, Fresenius, Other chain, Independent). See dbt
-- model `fct_dialysis_chain_star_mix` for the semantics -- crucially,
-- `n_unrated` is the count of facilities with a CMS-suppressed overall
-- rating and is intentionally surfaced so downstream views can pair it
-- with the mean-star column.
select
    chain_group,
    n_star_1,
    n_star_2,
    n_star_3,
    n_star_4,
    n_star_5,
    n_unrated,
    n_facilities_total,
    mean_star_rated,
    as_of
from main_marts.fct_dialysis_chain_star_mix
