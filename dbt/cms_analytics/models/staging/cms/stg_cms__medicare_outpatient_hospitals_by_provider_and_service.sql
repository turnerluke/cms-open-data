with source as (

    select * from {{ source('cms_raw', 'cms_medicare_outpatient_hospitals_by_provider_and_service') }}

),

renamed as (

    select
        -- identifiers (one row per hospital CCN per APC)
        -- CCN join key, conformed as in
        -- stg_cms__hospital_general_information
        upper(trim(rndrng_prvdr_ccn)) as ccn,
        lpad(cast(apc_cd as varchar), 4, '0') as apc_code,
        trim(apc_desc) as apc_description,
        trim(rndrng_prvdr_org_name) as provider_name,

        -- address
        nullif(trim(rndrng_prvdr_st), '') as street_address,
        nullif(trim(rndrng_prvdr_city), '') as city,
        trim(rndrng_prvdr_state_abrvtn) as state,
        trim(rndrng_prvdr_state_fips) as state_fips,
        rndrng_prvdr_zip5 as zip5,
        rndrng_prvdr_ruca as ruca_code,
        nullif(trim(rndrng_prvdr_ruca_desc), '') as ruca_description,

        -- utilization
        bene_cnt as beneficiary_count,
        capc_srvcs as comprehensive_apc_service_count,
        outlier_srvcs as outlier_service_count,

        -- payment averages
        avg_tot_sbmtd_chrgs as avg_total_submitted_charges,
        avg_mdcr_alowd_amt as avg_medicare_allowed_amount,
        avg_mdcr_pymt_amt as avg_medicare_payment_amount,
        avg_mdcr_outlier_amt as avg_medicare_outlier_amount

    from source

)

select * from renamed
