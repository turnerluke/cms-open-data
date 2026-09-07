with staged as (

    select * from {{ ref('stg_cms__home_health_care_agencies') }}

),

final as (

    select
        -- identifiers
        ccn,
        provider_name,

        -- address
        address,
        city,
        state,
        zip5,
        telephone_number,

        -- classification. Ownership arrives as `PROPRIETARY`,
        -- `NON-PROFIT`, `GOVERNMENT OPERATED`, or the `-` sentinel
        -- (2,157 of 12,460 agencies in the 2026-05 vintage carry the
        -- sentinel; nearly all of them — 2,154 of 2,157 — also have
        -- every `offers_*` flag null, so treat these as directory-only
        -- rows with no operating detail).
        -- Null the sentinel so the dim only carries real values.
        nullif(ownership_type, '-') as ownership_type,

        -- Medicare-certification date parsed at staging from the CMS
        -- `MM/DD/YYYY` string. One row in the 2026-05 vintage carries
        -- a `-` sentinel and arrives as NULL; every other agency is
        -- populated (min 1966-07-01, max 2025-12-26).
        certification_date,

        -- offered services (staging already maps `Yes`/`No` to
        -- boolean; the `-` sentinel and empty string arrive as NULL)
        offers_nursing_care,
        offers_physical_therapy,
        offers_occupational_therapy,
        offers_speech_pathology,
        offers_medical_social_services,
        offers_home_health_aide,

        -- overall Care Compare star rating (1-5 in 0.5-star
        -- increments; ~35% NULL when CMS reports it as not available
        -- — see `_footnote` for the reason code)
        quality_of_patient_care_star_rating,
        quality_of_patient_care_star_rating_footnote,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'home_health_care_agencies'
        ) as as_of
    from staged

)

select * from final
