with staged as (

    select * from {{ ref('stg_cms__doctors_and_clinicians_national_downloadable') }}

),

-- The National Downloadable file publishes one row per
-- (npi, individual_enrollment_id, organization_pac_id, address_id) —
-- 3.39M rows across 1.62M distinct NPIs. Multi-row NPIs are
-- clinicians with multiple enrollments, group memberships, or
-- practice locations. Gender and graduation_year are constant per
-- NPI (max distinct = 1), so `any_value` is deterministic. Primary
-- specialty varies for ~9.6K NPIs — we pick the most-frequent
-- primary_specialty per NPI, breaking ties alphabetically so the
-- collapse is deterministic across warehouse rebuilds. Names and
-- medical_school are near-constant (1 NPI has two last-name
-- spellings, 2 NPIs vary on first_name, 3 on middle_name, 2 on
-- medical_school) but we apply the same most-frequent +
-- alphabetical tiebreak so the dim is fully deterministic.

primary_specialty_ranked as (

    select
        npi,
        primary_specialty,
        row_number() over (
            partition by npi
            order by count(*) desc, primary_specialty asc
        ) as rn
    from staged
    where primary_specialty is not null
    group by 1, 2

),

primary_specialty_by_npi as (

    select
        npi,
        primary_specialty
    from primary_specialty_ranked
    where rn = 1

),

-- Same deterministic tiebreak for `credentials` (only 1 NPI in the
-- 2026-07-31 vintage has two distinct credentials, but a stable
-- rule makes future vintages reproducible), the four
-- near-constant name / school columns (first_name, middle_name,
-- last_name, medical_school — 1–3 NPIs each vary but the rule
-- keeps the dim reproducible), and `facility_name` /
-- `organization_pac_id` for the "primary" practice location.

credentials_ranked as (

    select
        npi,
        credentials,
        row_number() over (
            partition by npi
            order by count(*) desc, credentials asc
        ) as rn
    from staged
    where credentials is not null
    group by 1, 2

),

credentials_by_npi as (

    select
        npi,
        credentials
    from credentials_ranked
    where rn = 1

),

provider_first_name_ranked as (

    select
        npi,
        provider_first_name,
        row_number() over (
            partition by npi
            order by count(*) desc, provider_first_name asc
        ) as rn
    from staged
    where provider_first_name is not null
    group by 1, 2

),

provider_first_name_by_npi as (

    select
        npi,
        provider_first_name
    from provider_first_name_ranked
    where rn = 1

),

provider_middle_name_ranked as (

    select
        npi,
        provider_middle_name,
        row_number() over (
            partition by npi
            order by count(*) desc, provider_middle_name asc
        ) as rn
    from staged
    where provider_middle_name is not null
    group by 1, 2

),

provider_middle_name_by_npi as (

    select
        npi,
        provider_middle_name
    from provider_middle_name_ranked
    where rn = 1

),

provider_last_name_ranked as (

    select
        npi,
        provider_last_name,
        row_number() over (
            partition by npi
            order by count(*) desc, provider_last_name asc
        ) as rn
    from staged
    where provider_last_name is not null
    group by 1, 2

),

provider_last_name_by_npi as (

    select
        npi,
        provider_last_name
    from provider_last_name_ranked
    where rn = 1

),

medical_school_ranked as (

    select
        npi,
        medical_school,
        row_number() over (
            partition by npi
            order by count(*) desc, medical_school asc
        ) as rn
    from staged
    where medical_school is not null
    group by 1, 2

),

medical_school_by_npi as (

    select
        npi,
        medical_school
    from medical_school_ranked
    where rn = 1

),

primary_organization_ranked as (

    select
        npi,
        organization_pac_id,
        facility_name,
        row_number() over (
            partition by npi
            -- Prefer the organization the clinician has the most
            -- practice-location rows under; break ties on the org
            -- with the most reported members (proxy for the primary
            -- affiliation), then alphabetically by facility_name so
            -- the pick is deterministic.
            order by
                count(*) desc,
                max(organization_member_count) desc nulls last,
                facility_name asc
        ) as rn
    from staged
    where organization_pac_id is not null
    group by 1, 2, 3

),

primary_organization_by_npi as (

    select
        npi,
        organization_pac_id as primary_organization_pac_id,
        facility_name as primary_facility_name
    from primary_organization_ranked
    where rn = 1

),

collapsed as (

    select
        s.npi,

        -- Demographics: `gender`, `graduation_year`, and
        -- `provider_suffix` are constant per NPI in the 2026-07-31
        -- vintage, so `any_value` returns a stable pick. Names and
        -- `medical_school` use the most-frequent + alphabetical
        -- tiebreak (see the ranked CTEs above) — joined in `final`.
        any_value(s.provider_suffix) as provider_suffix,
        any_value(s.gender) as gender,
        any_value(s.graduation_year) as graduation_year,

        -- Telehealth flag: TRUE if the clinician bills telehealth on
        -- any of their enrollment rows, NULL otherwise. Staging emits
        -- only `TRUE` / `NULL` (raw `telehlth` is strictly `Y` or
        -- blank), so `bool_or` is exhaustive — a two-state result.
        bool_or(s.offers_telehealth) as offers_telehealth,

        -- Practice-location rollup. Excludes NULLs (solo-practice
        -- rows have no organization_pac_id).
        count(distinct s.address_id) as practice_location_count,
        count(distinct s.organization_pac_id) as organization_count,
        count(distinct s.state) as practice_state_count,
        count(distinct s.individual_enrollment_id) as enrollment_count

    from staged as s
    group by 1

),

final as (

    select
        c.npi,
        ln.provider_last_name,
        fn.provider_first_name,
        mn.provider_middle_name,
        c.provider_suffix,
        c.gender,
        cr.credentials,
        ms.medical_school,
        c.graduation_year,
        ps.primary_specialty,
        c.offers_telehealth,
        po.primary_organization_pac_id,
        po.primary_facility_name,
        c.practice_location_count,
        c.organization_count,
        c.practice_state_count,
        c.enrollment_count,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where
                vintages.dataset_key
                = 'doctors_and_clinicians_national_downloadable'
        ) as as_of

    from collapsed as c
    left join primary_specialty_by_npi as ps on c.npi = ps.npi
    left join credentials_by_npi as cr on c.npi = cr.npi
    left join primary_organization_by_npi as po on c.npi = po.npi
    left join provider_first_name_by_npi as fn on c.npi = fn.npi
    left join provider_middle_name_by_npi as mn on c.npi = mn.npi
    left join provider_last_name_by_npi as ln on c.npi = ln.npi
    left join medical_school_by_npi as ms on c.npi = ms.npi

)

select * from final
