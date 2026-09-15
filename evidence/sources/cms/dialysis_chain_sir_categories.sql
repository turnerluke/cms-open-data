-- Standardized infection ratio (SIR) categorical breakdown per chain.
-- SIR is the CMS-flagship dialysis outcome measure -- one row per
-- facility bucketed into 'Better than Expected', 'As Expected',
-- 'Worse than Expected', or 'Not Available' (suppressed). Displaying
-- the four categories side by side per chain shows both the outcome
-- distribution *and* the reporting gap (the fourth column) in one
-- visual.
with categories as (
    select 'Better than Expected' as category, 1 as category_sort
    union all
    select 'As Expected',          2
    union all
    select 'Worse than Expected',  3
    union all
    select 'Not Available',        4
),

groups as (
    select 'DaVita'      as chain_group, 1 as chain_sort
    union all
    select 'Fresenius',   2
    union all
    select 'Other chain', 3
    union all
    select 'Independent', 4
),

unpivoted as (
    select chain_group,
        'Better than Expected' as category, n_better_than_expected as facilities
    from main_marts.fct_dialysis_chain_measure
    where measure_code = 'sir'
    union all
    select chain_group, 'As Expected', n_as_expected
    from main_marts.fct_dialysis_chain_measure
    where measure_code = 'sir'
    union all
    select chain_group, 'Worse than Expected', n_worse_than_expected
    from main_marts.fct_dialysis_chain_measure
    where measure_code = 'sir'
    union all
    select chain_group, 'Not Available', n_not_available
    from main_marts.fct_dialysis_chain_measure
    where measure_code = 'sir'
)

select
    u.chain_group,
    g.chain_sort,
    u.category,
    c.category_sort,
    u.facilities
from unpivoted as u
inner join categories as c on u.category   = c.category
inner join groups     as g on u.chain_group = g.chain_group
order by g.chain_sort, c.category_sort
