with source as (

    select * from {{ source('cms_raw', 'cms_medicare_physician_by_geography_and_service') }}

),

renamed as (

    select
        -- geography grain columns. `geography_level` is 'National'
        -- (13,463 rows, all with `geography_code` NULL) or 'State'
        -- (254,887 rows, `geography_code` is a two-character FIPS-ish
        -- code — 50 states + DC use 2-digit numeric, plus five
        -- pseudo-codes 9A/9B/9C/9D/9E for Armed Forces regions,
        -- Unknown, and Foreign; five 'State' rows in the current
        -- vintage carry a NULL `geography_code` — CMS emits these as
        -- state-level aggregates whose state the reporting file failed
        -- to identify).
        trim(rndrng_prvdr_geo_lvl) as geography_level,
        nullif(trim(rndrng_prvdr_geo_cd), '') as geography_code,
        nullif(trim(rndrng_prvdr_geo_desc), '') as geography_description,

        -- HCPCS service attributes
        trim(hcpcs_cd) as hcpcs_code,
        trim(hcpcs_desc) as hcpcs_description,
        -- 'Y' Part-B drug HCPCS (15,435 rows), 'N' medical service
        -- (252,915). Never null.
        trim(hcpcs_drug_ind) as hcpcs_drug_indicator,
        -- Place of service: 'F' facility (140,017 rows), 'O'
        -- office / non-facility (128,333). Never null.
        trim(place_of_srvc) as place_of_service,

        -- rollup measures. All six measures are non-null on every
        -- row; CMS drops geography×HCPCS combinations with 10 or
        -- fewer beneficiaries from the file rather than suppressing
        -- in place (the same publication rule as the by-provider
        -- service file), so `total_beneficiaries` is never below 11
        -- while `total_rendering_providers` can be as low as 1 (a
        -- single provider serving 11+ beneficiaries for that code).
        tot_rndrng_prvdrs as total_rendering_providers,
        tot_benes as total_beneficiaries,
        tot_srvcs as total_services,
        tot_bene_day_srvcs as total_beneficiary_day_services,

        -- payment averages (per service).
        avg_sbmtd_chrg as avg_submitted_charge,
        avg_mdcr_alowd_amt as avg_medicare_allowed_amount,
        avg_mdcr_pymt_amt as avg_medicare_payment_amount,
        avg_mdcr_stdzd_amt as avg_medicare_standardized_amount

    from source

)

select * from renamed
