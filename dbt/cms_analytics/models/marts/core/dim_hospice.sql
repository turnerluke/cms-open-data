with staged as (

    select * from {{ ref('stg_cms__hospice_general_information') }}

),

final as (

    select
        -- identifiers
        ccn,
        facility_name,

        -- address
        address_line_1,
        address_line_2,
        city,
        state,
        zip5,
        county,
        telephone_number,

        -- CMS operational region (`1`..`10`, string) — flat directory
        -- attribute the source publishes; kept for regional rollups.
        cms_region,

        -- classification. Ownership arrives as `For-Profit`,
        -- `Non-Profit`, `Government`, `Other`,
        -- `Combination Government & Non-Profit`, or an empty string
        -- (1,560 of 6,669 hospices in the 2026-08 vintage — the
        -- source publishes a directory row with no ownership field).
        -- Nullify empty strings so the dim only carries real values.
        nullif(ownership_type, '') as ownership_type,

        -- Medicare-certification date parsed at staging from the CMS
        -- `MM/DD/YYYY` string. Every hospice in the 2026-08 vintage is
        -- populated (min 1983-11-01, max 2026-01-19).
        certification_date,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospice_general_information'
        ) as as_of
    from staged

)

select * from final
