-- Reporting rate per chain across every measure_code in
-- fct_dialysis_chain_measure. The reporting rate is
-- `n_facilities_reported / n_facilities_total` -- i.e. the share of
-- each chain's facility footprint that publishes a value for this
-- measure. Systematic gaps (e.g. Independent facilities reporting SIR
-- at ~43% vs 91-93% for the national chains) are the mechanism behind
-- the survivorship-bias caveat.
select
    m.measure_code,
    m.measure_name,
    m.chain_group,
    case m.chain_group
        when 'DaVita' then 1
        when 'Fresenius' then 2
        when 'Other chain' then 3
        when 'Independent' then 4
    end as chain_sort,
    m.n_facilities_reported,
    m.n_facilities_total,
    m.n_facilities_reported::double / m.n_facilities_total
        as reporting_rate
from main_marts.fct_dialysis_chain_measure as m
order by m.measure_code, chain_sort
