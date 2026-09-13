with source as (

    select * from {{ source('cms_raw', 'cms_medicare_physician_by_provider_and_service') }}

),

renamed as (

    select
        -- identifiers / grain (one row per rendering NPI × HCPCS ×
        -- place-of-service). All three columns are non-null on every
        -- row; empirical uniqueness confirmed in staging tests.
        lpad(cast(rndrng_npi as varchar), 10, '0') as npi,
        trim(hcpcs_cd) as hcpcs_code,
        -- Place of service: 'F' facility (hospital/ASC/SNF), 'O'
        -- office / non-facility. No nulls in the file.
        trim(place_of_srvc) as place_of_service,

        -- provider descriptors (denormalized from the by-provider file
        -- for at-a-glance service-level analysis without a join).
        trim(rndrng_prvdr_last_org_name) as provider_last_org_name,
        nullif(trim(rndrng_prvdr_first_name), '') as provider_first_name,
        nullif(trim(rndrng_prvdr_mi), '') as provider_middle_initial,
        nullif(trim(rndrng_prvdr_crdntls), '') as provider_credentials,
        -- entity code: 'I' individual (9,306,818 rows), 'O'
        -- organizational (474,855 rows).
        trim(rndrng_prvdr_ent_cd) as entity_code,

        -- address
        nullif(trim(rndrng_prvdr_st1), '') as street_address_1,
        nullif(trim(rndrng_prvdr_st2), '') as street_address_2,
        nullif(trim(rndrng_prvdr_city), '') as city,
        trim(rndrng_prvdr_state_abrvtn) as state,
        -- `state_fips` is `NULL` on exactly 5 rows (all
        -- state=`FM`/country=`US`, an obsolete Micronesia code in the
        -- upstream file); every other row carries a two-digit code.
        trim(rndrng_prvdr_state_fips) as state_fips,
        nullif(trim(rndrng_prvdr_zip5), '') as zip5,
        -- RUCA code carries meaningful decimal subcodes like 4.1;
        -- 5,291 rows (0.05%) are null — 4,984 U.S. rows without a
        -- ZIP-level RUCA plus 307 non-U.S. rows.
        rndrng_prvdr_ruca as ruca_code,
        nullif(trim(rndrng_prvdr_ruca_desc), '') as ruca_description,
        trim(rndrng_prvdr_cntry) as country,

        -- provider attributes
        nullif(trim(rndrng_prvdr_type), '') as provider_type,
        -- Medicare-participation indicator: 'Y' 9,779,092 rows or 'N'
        -- 2,581 rows. Never null.
        trim(rndrng_prvdr_mdcr_prtcptg_ind) as medicare_participating_indicator,

        -- HCPCS service attributes. `hcpcs_description` and
        -- `hcpcs_drug_indicator` are 1:1 with `hcpcs_code` in the
        -- current vintage (0 codes carry >1 description or >1 drug
        -- indicator) so downstream can safely rely on either for
        -- grouping.
        trim(hcpcs_desc) as hcpcs_description,
        -- 'Y' Part-B drug HCPCS (529,613 rows), 'N' medical service
        -- (9,252,060). Never null.
        trim(hcpcs_drug_ind) as hcpcs_drug_indicator,

        -- utilization. `total_beneficiaries` is never null and never
        -- below 11: CMS drops rows with 10 or fewer beneficiaries from
        -- the file rather than suppressing in place — the same
        -- publication rule as the Part D by-prescriber files, and
        -- unlike the by-provider summary file this dataset carries no
        -- separate suppression flag columns.
        tot_benes as total_beneficiaries,
        tot_srvcs as total_services,
        tot_bene_day_srvcs as total_beneficiary_day_services,

        -- payment averages (per service). The submitted-charge cap
        -- ($99,999.99) is a CMS-known artifact of the reporting file
        -- format, not real data — see the yml. All four amounts are
        -- non-null on every row.
        avg_sbmtd_chrg as avg_submitted_charge,
        avg_mdcr_alowd_amt as avg_medicare_allowed_amount,
        avg_mdcr_pymt_amt as avg_medicare_payment_amount,
        avg_mdcr_stdzd_amt as avg_medicare_standardized_amount

    from source

)

select * from renamed
