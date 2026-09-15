-- Chain-group x measure_code rollup of fct_dialysis_quality for the
-- DaVita-vs-Fresenius comparative analysis. Grain:
-- (chain_group, measure_code) -- 4 chain_groups x 27 measure codes =
-- 108 rows.
--
-- Aggregation semantics (bake these into any downstream reading of
-- this table):
--
--   * `is_reported = true` filter. Every score aggregation uses only
--     CMS-reported rows (availability_code = '001'). Suppressed rows
--     carry a NULL score_numeric and are intentionally excluded --
--     they are not zeros. Reporting rate itself matters analytically
--     (suppression may correlate with facility size, which differs by
--     chain), so `n_facilities_reported` / `n_facilities_total` are
--     both surfaced.
--
--   * Two mean flavours. `score_unweighted_mean` is the plain facility
--     mean -- gives every facility one vote regardless of size. It
--     answers "what does the typical facility in this chain look
--     like?". `score_weighted_mean` weights each facility by its
--     reported denominator (sum(score*denominator) / sum(denominator))
--     -- answers "what does the typical *patient / patient-month /
--     hospitalization* at this chain experience?". Big-facility
--     performance can dominate the weighted mean. For the three
--     measures without a per-row denominator upstream (five_star,
--     sir, hcp_vaccination) `score_weighted_mean` is NULL and the
--     unweighted mean is the only summary available.
--
--   * Weighting is safe within a measure_code because
--     denominator_unit is constant within a measure_code (verified by
--     a not_null-per-measure test on the source and enforced here via
--     `max(denominator_unit)` after grouping). Never sum denominators
--     across measure_codes -- units are mixed
--     (patients / hospitalizations / patient-months).
--
--   * Category counts. For the 11 measures CMS publishes a categorical
--     peer-comparison bucket for (smr / shr / srr / strr / sir / sedr /
--     ed30 / fyswr / pppw / smosr / fistula),
--     `n_better_than_expected`, `n_as_expected`, `n_worse_than_expected`,
--     and `n_not_available` are populated. Note that the ratio-family
--     category column carries the literal 'Not Available' on
--     suppressed rows -- those are counted separately and do not add
--     to the "reported" counts. Non-ratio measures leave all four
--     category counters NULL.

with facilities as (

    select
        ccn,
        {{ dialysis_chain_group('chain_organization') }} as chain_group
    from {{ ref('dim_dialysis_facility') }}

),

group_totals as (

    select
        chain_group,
        count(*) as n_facilities_total
    from facilities
    group by 1

),

quality as (

    select * from {{ ref('fct_dialysis_quality') }}

),

joined as (

    select
        f.chain_group,
        q.measure_code,
        q.measure_name,
        q.denominator_unit,
        q.is_reported,
        q.score_numeric,
        q.denominator,
        q.category
    from quality as q
    inner join facilities as f on q.ccn = f.ccn

),

aggregated as (

    select
        j.chain_group,
        j.measure_code,
        -- measure_name and denominator_unit are constant within a
        -- measure_code; carry them through with an any_value-style
        -- aggregate so the grain stays clean.
        max(j.measure_name) as measure_name,
        max(j.denominator_unit) as denominator_unit,
        count(*) filter (where j.is_reported) as n_facilities_reported,
        avg(j.score_numeric) filter (where j.is_reported)
            as score_unweighted_mean,
        sum(j.score_numeric * j.denominator) filter (where j.is_reported)
        / nullif(
            sum(j.denominator) filter (where j.is_reported), 0
        ) as score_weighted_mean,
        sum(j.denominator) filter (where j.is_reported)
            as total_denominator,
        -- Category counts. Only the standardized-ratio family (and a
        -- few others -- see fct_dialysis_quality) publish a category;
        -- non-ratio measures leave these NULL (count(*) filter over a
        -- never-matching predicate is 0, but we want NULL to signal
        -- "no category concept for this measure", so wrap in a
        -- conditional on whether any category value exists).
        case
            when count(j.category) > 0
                then count(*) filter (where j.category = 'Better than Expected')
        end as n_better_than_expected,
        case
            when count(j.category) > 0
                then count(*) filter (where j.category = 'As Expected')
        end as n_as_expected,
        case
            when count(j.category) > 0
                then count(*) filter (where j.category = 'Worse than Expected')
        end as n_worse_than_expected,
        case
            when count(j.category) > 0
                then count(*) filter (where j.category = 'Not Available')
        end as n_not_available
    from joined as j
    group by 1, 2

),

final as (

    select
        a.chain_group,
        a.measure_code,
        a.measure_name,
        a.denominator_unit,
        g.n_facilities_total,
        a.n_facilities_reported,
        a.score_unweighted_mean,
        a.score_weighted_mean,
        a.total_denominator,
        a.n_better_than_expected,
        a.n_as_expected,
        a.n_worse_than_expected,
        a.n_not_available,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'dialysis_facility_listing'
        ) as as_of
    from aggregated as a
    inner join group_totals as g on a.chain_group = g.chain_group

)

select * from final
