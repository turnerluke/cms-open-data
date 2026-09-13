-- Cross-file invariant between the physician-by-provider summary and
-- the physician-by-provider-and-service detail files. CMS drops rows
-- with 10 or fewer beneficiaries from the *detail* file rather than
-- suppressing in place, so per-NPI aggregates of the detail file are
-- bounded above by the summary totals. Mirrors the
-- `fct_prescriber_profile__detail_leq_profile_reconciliation` guard
-- from the Part D sprint (PR #149). Any row returned = a violation.
with detail as (
    select
        npi,
        count(distinct hcpcs_code) as detail_hcpcs_codes,
        sum(total_services) as detail_total_services,
        sum(avg_medicare_payment_amount * total_services) as detail_pymt
    from {{ ref('stg_cms__medicare_physician_by_provider_and_service') }}
    group by 1
),

summary as (
    select
        npi,
        total_hcpcs_codes,
        total_services,
        total_medicare_payment_amount
    from {{ ref('stg_cms__medicare_physician_by_provider') }}
)

select
    detail.npi,
    detail.detail_hcpcs_codes,
    summary.total_hcpcs_codes,
    detail.detail_total_services,
    summary.total_services,
    detail.detail_pymt,
    summary.total_medicare_payment_amount
from detail
inner join summary on detail.npi = summary.npi
where
    detail.detail_hcpcs_codes > summary.total_hcpcs_codes
    or detail.detail_total_services > summary.total_services + 0.01
    or detail.detail_pymt > summary.total_medicare_payment_amount + 1.0
