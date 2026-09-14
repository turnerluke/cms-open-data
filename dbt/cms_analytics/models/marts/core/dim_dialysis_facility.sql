with staged as (

    select * from {{ ref('stg_cms__dialysis_facility_listing') }}

),

final as (

    select
        -- identifiers
        ccn,
        facility_name,
        -- ESRD network 1..18 published as a text identifier; kept as
        -- string to match staging
        esrd_network,

        -- address
        address_line_1,
        address_line_2,
        city,
        state,
        zip5,
        county,
        telephone_number,

        -- classification
        is_for_profit,
        is_chain_owned,
        -- Chain organization; the literal string `Independent` appears
        -- iff `is_chain_owned = false` (staging invariant test verifies
        -- this at build time). Kept verbatim.
        chain_organization,

        -- service offerings
        offers_incenter_hemodialysis,
        offers_peritoneal_dialysis,
        offers_home_hemodialysis_training,
        offers_late_shift,

        -- capacity
        number_of_dialysis_stations,

        -- Medicare-certification date parsed at staging from the CMS
        -- `YYYY-MM-DD` string.
        certification_date,

        -- headline five-star rating (1-5; NULL for 491 rows that are
        -- CMS-suppressed with an availability code in `201`/`258`/`260`)
        five_star,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'dialysis_facility_listing'
        ) as as_of
    from staged

)

select * from final
