-- Chain-group means for the four quality measures the analysis
-- highlights in prose: standardized infection ratio (SIR), long-term
-- catheter use, hemoglobin < 10 g/dL, and arteriovenous-fistula use.
-- Each row carries both the facility-vote (unweighted) and patient-vote
-- (denominator-weighted) mean where CMS ships a per-row denominator,
-- so the page can show both flavours and note where they diverge.
--
-- The `chain_sort` / `measure_sort` columns keep chart series and table
-- rows in a deliberate reading order (SIR is the headline, then the
-- three percent-family clinical measures in descending gap).
with codes as (
    select 'sir'                as measure_code, 1 as measure_sort
    union all
    select 'long_term_catheter', 2
    union all
    select 'hgb_lt_10',          3
    union all
    select 'fistula',            4
),

groups as (
    select 'DaVita'      as chain_group, 1 as chain_sort
    union all
    select 'Fresenius',   2
    union all
    select 'Other chain', 3
    union all
    select 'Independent', 4
)

select
    m.chain_group,
    g.chain_sort,
    m.measure_code,
    c.measure_sort,
    m.measure_name,
    m.denominator_unit,
    m.n_facilities_reported,
    m.n_facilities_total,
    m.n_facilities_reported::double / m.n_facilities_total
        as reporting_rate,
    m.score_unweighted_mean,
    m.score_weighted_mean,
    m.total_denominator
from main_marts.fct_dialysis_chain_measure as m
inner join codes  as c on m.measure_code = c.measure_code
inner join groups as g on m.chain_group  = g.chain_group
order by c.measure_sort, g.chain_sort
