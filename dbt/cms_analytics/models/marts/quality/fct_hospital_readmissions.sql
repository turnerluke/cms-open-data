with staged as (

    select * from {{ ref('stg_cms__hospital_readmissions_reduction') }}

),

final as (

    select
        -- identifiers
        facility_id as ccn,
        -- Strip the `READM-30-` prefix and `-HRRP` suffix to leave the
        -- clinical condition slug: AMI, CABG, COPD, HF, HIP-KNEE, PN
        replace(replace(measure_name, 'READM-30-', ''), '-HRRP', '')
            as condition,

        -- results
        excess_readmission_ratio,
        predicted_readmission_rate,
        expected_readmission_rate,

        -- volumes
        number_of_discharges,
        number_of_readmissions,
        is_too_few_to_report,

        -- footnote passed through — pairs with NULL numeric columns
        -- to explain suppressed values
        footnote,

        -- derived: HRRP payment penalty applies when a hospital's
        -- risk-adjusted readmissions exceed CMS's expected value
        -- (ERR > 1). NULL when ERR is NULL (measure not eligible /
        -- suppressed for the hospital).
        case
            when excess_readmission_ratio is null then null
            else excess_readmission_ratio > 1
        end as is_penalized,

        -- measurement period — single window in this vintage
        start_date as period_start_date,
        end_date as period_end_date,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'hospital_readmissions_reduction'
        ) as as_of
    from staged

)

select * from final
