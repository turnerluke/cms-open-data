-- Facility five-star distribution by chain_group. Grain: chain_group
-- (four rows).
--
-- Star source of truth: `dim_dialysis_facility.five_star`, not the
-- `five_star` row in `fct_dialysis_quality`. Both come from the same
-- CMS column, but the dim exposes it as a nullable smallint (NULL =
-- CMS-suppressed rating) while the fact carries every facility with a
-- suppression code. For a facility-count star-mix the dim is the
-- natural grain (one row per CCN, no measure filter needed).
--
-- `n_unrated` is the count of facilities where CMS suppressed the
-- overall five-star rating (availability code in 201 / 258 / 260 --
-- typically too-few-patients or new-facility). Reporting the unrated
-- count matters analytically because Independent facilities are much
-- less likely to be rated than the national chains, so any headline
-- "average stars" comparison that silently drops unrated rows
-- understates the size gap.

with facilities as (

    select
        ccn,
        five_star,
        {{ dialysis_chain_group('chain_organization') }} as chain_group
    from {{ ref('dim_dialysis_facility') }}

),

final as (

    select
        chain_group,
        count(*) filter (where five_star = 1) as n_star_1,
        count(*) filter (where five_star = 2) as n_star_2,
        count(*) filter (where five_star = 3) as n_star_3,
        count(*) filter (where five_star = 4) as n_star_4,
        count(*) filter (where five_star = 5) as n_star_5,
        count(*) filter (where five_star is null) as n_unrated,
        count(*) as n_facilities_total,
        avg(cast(five_star as double)) as mean_star_rated,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'dialysis_facility_listing'
        ) as as_of
    from facilities
    group by 1

)

select * from final
