with staged as (

    select * from {{ ref('stg_cms__long_term_care_hospital_general') }}

),

final as (

    select
        -- identifiers
        -- Every LTCH CCN in the current vintage is six digits (no
        -- letter-suffixed CCNs), reflecting that long-term care
        -- hospitals are freestanding facilities rather than units
        -- embedded in a host acute hospital.
        ccn,
        provider_name,

        -- address
        address_line_1,
        address_line_2,
        city,
        state,
        zip5,
        county,
        telephone_number,

        -- CMS operational region (`1`..`10`, string)
        cms_region,

        -- classification
        ownership_type,

        -- Medicare-certification date parsed at staging from the CMS
        -- `MM/DD/YYYY` string.
        certification_date,

        -- capacity (5 of 311 rows carry a `-` placeholder upstream,
        -- nulled at staging)
        total_number_of_beds,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'long_term_care_hospital_general'
        ) as as_of
    from staged

)

select * from final
