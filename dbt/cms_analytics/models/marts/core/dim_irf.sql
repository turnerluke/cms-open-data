with staged as (

    select * from {{ ref('stg_cms__inpatient_rehabilitation_facility_general') }}

),

final as (

    select
        -- identifiers
        -- IRF CCNs are six alphanumeric: 410 freestanding rehab
        -- hospitals with an all-numeric CCN, and 812 IRF units
        -- embedded in an acute hospital, encoded with a letter in
        -- position 3 (`T` for standard rehab units, `R` for
        -- critical-access rehab units). Kept verbatim so the key
        -- round-trips against other Care Compare files.
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

        -- Freestanding vs hospital-embedded designation derived from
        -- the CCN encoding above. Non-numeric CCNs (letter in pos 3)
        -- are units embedded in a parent acute hospital; numeric CCNs
        -- are freestanding IRF hospitals.
        case
            when ccn ~ '^[0-9]{6}$' then 'Freestanding'
            when substr(ccn, 3, 1) in ('T', 'R') then 'Hospital unit'
        end as facility_type,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'inpatient_rehabilitation_facility_general'
        ) as as_of
    from staged

)

select * from final
