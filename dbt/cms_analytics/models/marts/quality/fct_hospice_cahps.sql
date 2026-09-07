with provider as (

    select * from {{ ref('stg_cms__hospice_cahps_provider') }}

),

national as (

    -- national benchmark: 21 rows, one per BBV/MBV/TBV measure code.
    -- There is NO national row for `SUMMARY_STAR_RATING`, and one
    -- measure (`EMO_REL_MBV`) ships `Not Applicable` as its national
    -- score in the current vintage — both surface as NULL after the
    -- left join / numeric cast below.
    select
        measure_code,
        try_cast(nullif(score, 'Not Applicable') as double) as national_value
    from {{ ref('stg_cms__hospice_cahps_national') }}

),

vintage as (

    -- the provider and national files come from the same DKAN
    -- publisher and share a snapshot date in the current vintage; a
    -- future desync would need to split `as_of` per source rather
    -- than being silently collapsed
    select vintages.modified as as_of
    from {{ ref('stg_cms__dataset_vintages') }} as vintages
    where vintages.dataset_key = 'hospice_cahps_provider'

),

parsed as (

    select
        provider.ccn,
        provider.measure_code,
        provider.measure_name,
        -- provider score in the source is a text column that carries
        -- three shapes: numeric bottom/middle/top-box percentages
        -- (0-100) on the `_BBV/_MBV/_TBV` measures, the sentinel
        -- `Not Available` (suppressed with a footnote reason) and
        -- `Not Applicable` (used for the `SUMMARY_STAR_RATING` rows,
        -- whose value lives in `star_rating` instead). `score_numeric`
        -- is NULL for both sentinels; the raw text stays as `score`
        -- so analysts can tell those apart.
        provider.score,
        try_cast(nullif(nullif(provider.score, 'Not Available'), 'Not Applicable') as double)
            as score_numeric,
        -- star_rating is populated only on `SUMMARY_STAR_RATING` rows
        -- (2,164 of 6,669 hospices in the current vintage; the rest
        -- carry footnoted `Not Applicable`); staging already cast the
        -- numeric 1-5 values, mapping non-numeric text to NULL
        provider.star_rating,
        provider.footnote as score_footnote,
        -- national benchmark, aligned by measure_code. NULL for
        -- `SUMMARY_STAR_RATING` (no national row published) and for
        -- `EMO_REL_MBV` (national ships `Not Applicable`).
        national.national_value,
        -- CAHPS period is a single rolling multi-year window per
        -- vintage, formatted as `MM/DD/YYYY-MM/DD/YYYY` (NO spaces
        -- around the dash — unlike the provider-quality file). Parse
        -- by splitting on the middle `-`, which the file's fixed
        -- 10-character date widths let us locate deterministically.
        cast(strptime(substr(provider.measure_date_range, 1, 10), '%m/%d/%Y') as date)
            as period_start_date,
        cast(strptime(substr(provider.measure_date_range, 12, 10), '%m/%d/%Y') as date)
            as period_end_date,
        vintage.as_of
    from provider
    left join national on provider.measure_code = national.measure_code
    cross join vintage

),

final as (

    -- rows whose score is null / suppressed are kept so measure
    -- coverage per hospice stays analyzable
    select
        ccn,
        measure_code,
        measure_name,
        score,
        score_numeric,
        star_rating,
        score_footnote,
        national_value,
        period_start_date,
        period_end_date,
        as_of
    from parsed

)

select * from final
