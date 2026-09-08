with staged as (

    select * from {{ ref('stg_cms__doctors_and_clinicians_facility_affiliations') }}

),

final as (

    select
        -- Grain: (`npi`, `individual_pac_id`, `ccn`) — the same
        -- three-column key the staging model asserts unique on. A
        -- clinician with two PECOS enrollment records at the same
        -- facility appears twice; the pair-with-facility edge is
        -- unique on this triple.
        npi,
        individual_pac_id,
        facility_type,
        ccn as facility_ccn,

        -- Sub-unit CCN, populated only for the small tail of rows
        -- where a hospital breaks its affiliation into distinct
        -- service units (~9K rows). Kept for provenance.
        facility_unit_ccn,

        -- Foreign-key columns per facility family. Each is populated
        -- only when `facility_type` matches, so joins from the
        -- bridge to a specific dim on `.._ccn` can use the typed
        -- key without an additional facility_type filter. Dialysis,
        -- IRF, and LTCH have no dim in the warehouse (2026-07-31
        -- vintage) — their rows carry the raw CCN in
        -- `facility_ccn` with `facility_type` but no typed FK.
        case
            when facility_type = 'Hospital' then ccn
        end as hospital_ccn,
        case
            when facility_type = 'Nursing home' then ccn
        end as nursing_home_ccn,
        case
            when facility_type = 'Home health agency' then ccn
        end as home_health_agency_ccn,
        case
            when facility_type = 'Hospice' then ccn
        end as hospice_ccn,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where
                vintages.dataset_key
                = 'doctors_and_clinicians_facility_affiliations'
        ) as as_of

    from staged

)

select * from final
