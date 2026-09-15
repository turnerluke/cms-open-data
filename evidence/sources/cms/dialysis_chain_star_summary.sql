-- One-row-per-chain summary paired with the star-mix table: mean stars
-- *among rated facilities only* (the CMS default when they report an
-- "average star"), the unrated share, and the total facility count.
-- Pairing these three columns in a single table forces any reader to
-- see the unrated share alongside the mean -- the reason CMS's headline
-- averages understate the gap.
select
    chain_group,
    case chain_group
        when 'DaVita' then 1
        when 'Fresenius' then 2
        when 'Other chain' then 3
        when 'Independent' then 4
    end as chain_sort,
    n_facilities_total,
    n_facilities_total - n_unrated as n_rated,
    n_unrated,
    n_unrated::double / n_facilities_total as unrated_share,
    mean_star_rated
from main_marts.fct_dialysis_chain_star_mix
order by chain_sort
