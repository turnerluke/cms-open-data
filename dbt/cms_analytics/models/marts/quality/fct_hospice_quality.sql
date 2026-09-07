with source as (

    select * from {{ ref('stg_cms__hospice_provider_quality') }}

),

parsed as (

    select
        ccn,
        measure_code,
        measure_name,
        -- score in the source is a single text column that mixes three
        -- shapes across measures: numeric (some with thousands commas
        -- like `1,152`), boolean `Yes`/`No` (four measures — the two
        -- `Bene_*_Pct` "served at least 1 patient" flags and the two
        -- `Provided_Home_Care_*` care-mix flags), and the `Not
        -- Available` sentinel (with an optional footnote parenthetical
        -- like `Not Available(12)`). `score` here keeps the raw text
        -- so analysts can distinguish `Yes` / `No` from a suppression;
        -- `score_numeric` is the strict-cast numeric form (comma
        -- stripped) and is `NULL` for the boolean and sentinel rows.
        nullif(score, '') as score,
        case
            when score in ('Yes', 'No') then null
            when score like 'Not Available%' then null
            else try_cast(replace(score, ',', '') as double)
        end as score_numeric,
        -- `-` is the file's "no footnote" sentinel; footnote codes stay
        -- as text (multi-code values like `2,5` occur, so this is not a
        -- single numeric identifier)
        nullif(footnote, '-') as score_footnote,
        -- source period is `MM/DD/YYYY - MM/DD/YYYY` (with spaces
        -- around the dash — the CAHPS files use a no-space variant).
        -- strptime is strict: a malformed value errors at build time
        -- rather than silently becoming NULL, which is the trap the
        -- home-health / nursing-home facts already flagged.
        cast(strptime(trim(split_part(measure_date_range, '-', 1)), '%m/%d/%Y') as date)
            as period_start_date,
        cast(strptime(trim(split_part(measure_date_range, '-', 2)), '%m/%d/%Y') as date)
            as period_end_date,
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospice_provider_quality'
        ) as as_of
    from source

),

final as (

    -- rows whose score is null / suppressed / non-numeric are kept so
    -- measure coverage per hospice stays analyzable
    select
        ccn,
        measure_code,
        measure_name,
        score,
        score_numeric,
        score_footnote,
        period_start_date,
        period_end_date,
        as_of
    from parsed

)

select * from final
