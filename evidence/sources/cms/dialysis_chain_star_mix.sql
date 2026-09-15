-- Long-form star-mix rows for the chain-comparison stacked bar. One row
-- per (chain_group, star bucket) with a stable sort_order so 1★–5★ and
-- the `(Unrated)` bucket stack in a natural reading order. The unrated
-- bucket is intentionally included so the visual reconciles to
-- `n_facilities_total` per chain -- the whole point of the page is that
-- silently dropping unrated facilities hides a large selection effect
-- for Independents.
with chain_order as (
    select chain_group, n_facilities_total,
        case chain_group
            when 'DaVita' then 1
            when 'Fresenius' then 2
            when 'Other chain' then 3
            when 'Independent' then 4
        end as chain_sort
    from main_marts.fct_dialysis_chain_star_mix
),

unpivoted as (
    select chain_group, '1 star' as star_bucket, 1 as sort_order,
        n_star_1 as facilities
    from main_marts.fct_dialysis_chain_star_mix
    union all
    select chain_group, '2 stars', 2, n_star_2
    from main_marts.fct_dialysis_chain_star_mix
    union all
    select chain_group, '3 stars', 3, n_star_3
    from main_marts.fct_dialysis_chain_star_mix
    union all
    select chain_group, '4 stars', 4, n_star_4
    from main_marts.fct_dialysis_chain_star_mix
    union all
    select chain_group, '5 stars', 5, n_star_5
    from main_marts.fct_dialysis_chain_star_mix
    union all
    select chain_group, '(Unrated)', 6, n_unrated
    from main_marts.fct_dialysis_chain_star_mix
)

select
    u.chain_group,
    c.chain_sort,
    u.star_bucket,
    u.sort_order,
    u.facilities,
    u.facilities::double / c.n_facilities_total as share
from unpivoted as u
inner join chain_order as c on u.chain_group = c.chain_group
order by c.chain_sort, u.sort_order
