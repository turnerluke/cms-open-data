with source as (

    select * from {{ source('cms_raw', 'cms_medicare_part_d_prescribers_by_provider_and_drug') }}

),

renamed as (

    select
        -- identifiers (one row per prescriber NPI per brand/generic drug)
        lpad(cast(prscrbr_npi as varchar), 10, '0') as npi,
        trim(prscrbr_last_org_name) as prescriber_last_org_name,
        nullif(trim(prscrbr_first_name), '') as prescriber_first_name,
        nullif(trim(prscrbr_city), '') as city,
        trim(prscrbr_state_abrvtn) as state,
        trim(prscrbr_state_fips) as state_fips,
        nullif(trim(prscrbr_type), '') as prescriber_type,
        nullif(trim(prscrbr_type_src), '') as prescriber_type_source,
        nullif(trim(brnd_name), '') as brand_name,
        nullif(trim(gnrc_name), '') as generic_name,

        -- utilization and cost, all beneficiaries
        tot_clms as total_claims,
        tot_30day_fills as total_30day_fills,
        tot_day_suply as total_day_supply,
        tot_drug_cst as total_drug_cost,
        tot_benes as total_beneficiaries,

        -- utilization and cost, beneficiaries aged 65 and over.
        -- ge65_suppression_flag / ge65_beneficiary_suppression_flag are
        -- three-valued: '*' means the counts were below CMS's disclosure
        -- threshold, '#' means counter-suppressed so the suppressed
        -- value can't be recalculated from the totals, and null means
        -- disclosed
        nullif(trim(ge65_sprsn_flag), '') as ge65_suppression_flag,
        ge65_tot_clms as ge65_total_claims,
        ge65_tot_30day_fills as ge65_total_30day_fills,
        ge65_tot_day_suply as ge65_total_day_supply,
        ge65_tot_drug_cst as ge65_total_drug_cost,
        nullif(trim(ge65_bene_sprsn_flag), '') as ge65_beneficiary_suppression_flag,
        ge65_tot_benes as ge65_total_beneficiaries

    from source

)

select * from renamed
