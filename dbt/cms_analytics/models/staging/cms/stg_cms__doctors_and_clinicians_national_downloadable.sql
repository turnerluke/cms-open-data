with source as (

    select * from {{ source('cms_raw', 'cms_doctors_and_clinicians_national_downloadable') }}

),

renamed as (

    select
        -- identifiers (grain: npi, ind_enrl_id, org_pac_id, adrs_id)
        lpad(cast(npi as varchar), 10, '0') as npi,
        trim(ind_pac_id) as individual_pac_id,
        nullif(trim(ind_enrl_id), '') as individual_enrollment_id,

        -- provider name
        nullif(trim(provider_last_name), '') as provider_last_name,
        nullif(trim(provider_first_name), '') as provider_first_name,
        nullif(trim(provider_middle_name), '') as provider_middle_name,
        nullif(trim(suff), '') as provider_suffix,

        -- demographics / credentials
        nullif(trim(gndr), '') as gender,
        nullif(trim(cred), '') as credentials,
        nullif(trim(med_sch), '') as medical_school,
        try_cast(grd_yr as int) as graduation_year,

        -- specialty
        nullif(trim(pri_spec), '') as primary_specialty,
        nullif(trim(sec_spec_1), '') as secondary_specialty_1,
        nullif(trim(sec_spec_2), '') as secondary_specialty_2,
        nullif(trim(sec_spec_3), '') as secondary_specialty_3,
        nullif(trim(sec_spec_4), '') as secondary_specialty_4,
        -- `sec_spec_all` is the pipe-joined concatenation of the
        -- populated `sec_spec_1..4`; kept verbatim to preserve the
        -- upstream ordering used by CMS's search UI.
        nullif(trim(sec_spec_all), '') as secondary_specialty_all,

        -- Telehealth service flag: `Y` on providers who bill
        -- telehealth-eligible codes; empty maps to `NULL` (does not
        -- imply the provider does not offer telehealth).
        -- `NULL` when the raw flag is blank (which does not
        -- affirmatively mean the clinician does not offer
        -- telehealth), true when CMS marks it `Y`.
        case when telehlth = 'Y' then true end as offers_telehealth,

        -- practice-location facility (populated for the ~90% of
        -- rows tied to an org enrollment; `NULL` for solo-practice
        -- providers)
        nullif(trim(facility_name), '') as facility_name,
        nullif(trim(org_pac_id), '') as organization_pac_id,
        try_cast(num_org_mem as int) as organization_member_count,

        -- practice-location address
        nullif(trim(adr_ln_1), '') as address_line_1,
        nullif(trim(adr_ln_2), '') as address_line_2,
        -- Line-2 suppression flag: `Y` means CMS scrubbed
        -- `adr_ln_2` because it looked like a PO Box that
        -- publishing would leak; treat like a censored value.
        coalesce(ln_2_sprs = 'Y', false) as address_line_2_suppressed,
        nullif(trim(citytown), '') as city,
        trim(state) as state,
        -- `zip_code` arrives 5-digit or 9-digit (ZIP+4). Split so
        -- downstream joins can key on the always-present 5-digit
        -- form while preserving the +4 extension.
        substr(zip_code, 1, 5) as zip5,
        case when len(zip_code) = 9 then substr(zip_code, 6, 4) end as zip4,
        nullif(trim(telephone_number), '') as telephone_number,

        -- Medicare-assignment indicators: `Y` accepts assignment;
        -- `M` accepts on a claim-by-claim basis (Medicare
        -- Participation Agreement partial).
        trim(ind_assgn) as individual_medicare_assignment,
        trim(grp_assgn) as group_medicare_assignment,

        -- Address identifier — internal CMS surrogate that keys
        -- rows with the same practice location together; used with
        -- `npi` and `ind_enrl_id` to unique-identify a row.
        trim(adrs_id) as address_id

    from source

)

select * from renamed
