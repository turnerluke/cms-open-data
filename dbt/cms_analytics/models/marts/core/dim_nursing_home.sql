with provider as (

    select * from {{ ref('stg_cms__nursing_home_provider_info') }}

),

-- Real owner/manager records only: the 658 `Ownership Data Not
-- Available` placeholder rows carry a null owner_name and would
-- otherwise inflate every rollup by one phantom owner.
owners as (

    select * from {{ ref('stg_cms__nursing_home_ownership') }}
    where owner_name is not null

),

-- Role buckets. `direct` includes partnership interests: a general
-- or limited partner is a direct equity holder in the SNF's
-- operating entity. Mortgage- and security-interest holders are
-- creditors (secured lenders), not owners, and get their own
-- `creditor_count` — they still count toward the superset
-- `owner_count` because the source file lists them as ownership
-- rows, but they are excluded from both direct and indirect equity
-- buckets. All remaining roles (officers, directors, managing
-- employees, trustees, ADPs, governing-body members) are non-equity
-- control roles and only feed `owner_count`.
ownership_rollup as (

    select
        ccn,
        count(distinct owner_name) as owner_count,
        count(
            distinct case
                when
                    owner_role in (
                        '5% OR GREATER DIRECT OWNERSHIP INTEREST',
                        'DIRECT OWNERSHIP INTEREST',
                        'GENERAL PARTNERSHIP INTEREST',
                        'LIMITED PARTNERSHIP INTEREST'
                    )
                    then owner_name
            end
        ) as direct_owner_count,
        count(
            distinct case
                when
                    owner_role in (
                        '5% OR GREATER INDIRECT OWNERSHIP INTEREST',
                        'INDIRECT OWNERSHIP INTEREST'
                    )
                    then owner_name
            end
        ) as indirect_owner_count,
        count(
            distinct case
                when
                    owner_role in (
                        '5% OR GREATER MORTGAGE INTEREST',
                        '5% OR GREATER SECURITY INTEREST'
                    )
                    then owner_name
            end
        ) as creditor_count
    from owners
    group by 1

),

-- One row per home: the direct-equity holder with the largest
-- reported stake. Partnership rows carry no ownership_percentage
-- upstream (0 of 1,210 partnership rows report one), so widening
-- the candidate pool doesn't change any pct values; it only fills
-- 139 previously-null names on partnership-only CCNs (ties broken
-- alphabetically). Percentage sorts nulls last so direct-interest
-- holders with reported stakes always win over partners.
largest_direct_owner as (

    select
        ccn,
        owner_name as largest_direct_owner_name,
        owner_type as largest_direct_owner_type,
        ownership_percentage as largest_direct_owner_pct
    from owners
    where
        owner_role in (
            '5% OR GREATER DIRECT OWNERSHIP INTEREST',
            'DIRECT OWNERSHIP INTEREST',
            'GENERAL PARTNERSHIP INTEREST',
            'LIMITED PARTNERSHIP INTEREST'
        )
    qualify
        row_number() over (
            partition by ccn
            order by ownership_percentage desc nulls last, owner_name asc
        ) = 1

),

final as (

    select
        -- identifiers
        provider.ccn,
        provider.provider_name,
        provider.legal_business_name,

        -- address
        provider.address,
        provider.city,
        provider.state,
        provider.zip5,
        provider.county,
        provider.telephone_number,
        provider.latitude,
        provider.longitude,

        -- classification
        provider.ownership_type,
        provider.provider_type,
        provider.is_urban,
        provider.resides_in_hospital,
        provider.is_continuing_care_retirement_community,
        provider.special_focus_status,
        provider.first_approved_date,

        -- capacity
        provider.number_of_certified_beds,
        provider.average_residents_per_day,

        -- chain affiliation
        provider.chain_id,
        provider.chain_name,
        provider.number_of_facilities_in_chain,

        -- status flags
        provider.has_abuse_icon,
        provider.changed_ownership_in_last_12_months,

        -- star ratings
        provider.overall_rating,
        provider.health_inspection_rating,
        provider.qm_rating,
        provider.staffing_rating,

        -- staffing
        provider.reported_total_nurse_staffing_hours_per_resident_per_day,
        provider.reported_rn_staffing_hours_per_resident_per_day,
        provider.total_nursing_staff_turnover_pct,
        provider.registered_nurse_turnover_pct,

        -- ownership rollup (0 counts for the 658 homes whose only
        -- ownership row is the placeholder)
        coalesce(ownership_rollup.owner_count, 0) as owner_count,
        coalesce(ownership_rollup.direct_owner_count, 0) as direct_owner_count,
        coalesce(ownership_rollup.indirect_owner_count, 0) as indirect_owner_count,
        coalesce(ownership_rollup.creditor_count, 0) as creditor_count,
        largest_direct_owner.largest_direct_owner_name,
        largest_direct_owner.largest_direct_owner_type,
        largest_direct_owner.largest_direct_owner_pct,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'nursing_home_provider_info'
        ) as as_of
    from provider
    left join ownership_rollup
        on provider.ccn = ownership_rollup.ccn
    left join largest_direct_owner
        on provider.ccn = largest_direct_owner.ccn

)

select * from final
