-- TODO: the two utilization source files are single latest-vintage
-- snapshots with no year column, so this fact has no spending_year.
-- Take the year from dataset-vintage tracking before moving to a
-- ccn × year grain.

with inpatient as (

    select * from {{ ref('stg_cms__medicare_inpatient_hospitals_by_provider') }}

),

outpatient as (

    -- roughly 45% of ccn × apc rows are fully disclosure-suppressed
    -- (every measure null; `comprehensive_apc_service_count is null`
    -- marks them). sum() skips nulls, so suppressed rows drop out of
    -- the totals, and a hospital whose rows are all suppressed keeps
    -- null totals instead of a misleading 0. the source publishes
    -- per-service averages rather than totals, so dollar totals are
    -- reconstructed as avg × service count over disclosed rows.
    select
        ccn,
        count(distinct apc_code) as outpatient_apc_count,
        count(distinct case when comprehensive_apc_service_count is null then apc_code end)
            as outpatient_suppressed_apc_count,
        sum(beneficiary_count) as outpatient_total_beneficiaries,
        sum(comprehensive_apc_service_count) as outpatient_total_services,
        sum(outlier_service_count) as outpatient_total_outlier_services,
        sum(avg_total_submitted_charges * comprehensive_apc_service_count)
            as outpatient_estimated_submitted_charges,
        sum(avg_medicare_allowed_amount * comprehensive_apc_service_count)
            as outpatient_estimated_medicare_allowed_amount,
        sum(avg_medicare_payment_amount * comprehensive_apc_service_count)
            as outpatient_estimated_medicare_payment_amount,
        sum(avg_medicare_outlier_amount * outlier_service_count)
            as outpatient_estimated_medicare_outlier_amount
    from {{ ref('stg_cms__medicare_outpatient_hospitals_by_provider_and_service') }}
    group by 1

),

final as (

    -- full outer join: a hospital may appear in either file alone
    -- (inpatient-only or outpatient-only) and is kept either way
    select
        coalesce(inpatient.ccn, outpatient.ccn) as ccn,

        -- inpatient utilization and payments (one source row per ccn)
        inpatient.total_beneficiaries as inpatient_total_beneficiaries,
        inpatient.total_discharges as inpatient_total_discharges,
        inpatient.total_covered_days as inpatient_total_covered_days,
        inpatient.total_days as inpatient_total_days,
        inpatient.total_submitted_covered_charges as inpatient_total_submitted_covered_charges,
        inpatient.total_payment_amount as inpatient_total_payment_amount,
        inpatient.total_medicare_payment_amount as inpatient_total_medicare_payment_amount,
        inpatient.avg_hcc_risk_score as inpatient_avg_hcc_risk_score,

        -- outpatient aggregates (rolled up from ccn × apc)
        outpatient.outpatient_apc_count,
        outpatient.outpatient_suppressed_apc_count,
        outpatient.outpatient_total_beneficiaries,
        outpatient.outpatient_total_services,
        outpatient.outpatient_total_outlier_services,
        outpatient.outpatient_estimated_submitted_charges,
        outpatient.outpatient_estimated_medicare_allowed_amount,
        outpatient.outpatient_estimated_medicare_payment_amount,
        outpatient.outpatient_estimated_medicare_outlier_amount,

        -- derived per-unit metrics
        inpatient.total_medicare_payment_amount / nullif(inpatient.total_discharges, 0)
            as inpatient_medicare_payment_per_discharge,
        inpatient.total_payment_amount / nullif(inpatient.total_discharges, 0)
            as inpatient_payment_per_discharge,
        inpatient.total_days / nullif(inpatient.total_discharges, 0)
            as inpatient_avg_length_of_stay,
        outpatient.outpatient_estimated_medicare_payment_amount
        / nullif(outpatient.outpatient_total_services, 0)
            as outpatient_medicare_payment_per_service
    from inpatient
    full outer join outpatient on inpatient.ccn = outpatient.ccn

)

select * from final
