with source as (

    select * from {{ source('cms_raw', 'cms_doctors_and_clinicians_facility_affiliations') }}

),

renamed as (

    select
        -- identifiers (grain: npi, ind_pac_id, ccn)
        lpad(cast(npi as varchar), 10, '0') as npi,
        trim(ind_pac_id) as individual_pac_id,

        -- provider name
        nullif(trim(provider_last_name), '') as provider_last_name,
        nullif(trim(provider_first_name), '') as provider_first_name,
        nullif(trim(provider_middle_name), '') as provider_middle_name,
        nullif(trim(suff), '') as provider_suffix,

        -- facility
        trim(facility_type) as facility_type,
        -- The primary CCN join key. Facility CCNs cover multiple
        -- provider families (hospital numeric, nursing-home
        -- alphanumeric, etc.) so downstream joins pick the right
        -- dim on `facility_type`.
        upper(trim(facility_affiliations_certification_number)) as ccn,
        -- Populated only for a small tail (~9K rows) — the
        -- unit-of-service CCN when a hospital breaks its
        -- affiliation into sub-units. Kept for provenance.
        nullif(upper(trim(facility_type_certification_number)), '') as facility_unit_ccn

    from source

)

select * from renamed
