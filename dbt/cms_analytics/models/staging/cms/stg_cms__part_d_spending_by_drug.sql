with source as (

    select * from {{ source('cms_raw', 'cms_part_d_spending_by_drug') }}

),

renamed as (

    select
        -- identifiers (one row per brand / generic / manufacturer)
        nullif(trim(brnd_name), '') as brand_name,
        nullif(trim(gnrc_name), '') as generic_name,
        trim(mftr_name) as manufacturer_name,
        try_cast(tot_mftr as int) as total_manufacturers,

        -- 2020 spending
        tot_spndng_2020 as total_spending_2020,
        tot_dsg_unts_2020 as total_dosage_units_2020,
        tot_clms_2020 as total_claims_2020,
        tot_benes_2020 as total_beneficiaries_2020,
        avg_spnd_per_dsg_unt_wghtd_2020 as avg_spending_per_dosage_unit_weighted_2020,
        avg_spnd_per_clm_2020 as avg_spending_per_claim_2020,
        avg_spnd_per_bene_2020 as avg_spending_per_beneficiary_2020,
        -- is_outlier_* flags are three-valued: null when the drug
        -- wasn't marketed that year (applies to every year below)
        outlier_flag_2020 = 1 as is_outlier_2020,

        -- 2021 spending
        tot_spndng_2021 as total_spending_2021,
        tot_dsg_unts_2021 as total_dosage_units_2021,
        tot_clms_2021 as total_claims_2021,
        tot_benes_2021 as total_beneficiaries_2021,
        avg_spnd_per_dsg_unt_wghtd_2021 as avg_spending_per_dosage_unit_weighted_2021,
        avg_spnd_per_clm_2021 as avg_spending_per_claim_2021,
        avg_spnd_per_bene_2021 as avg_spending_per_beneficiary_2021,
        outlier_flag_2021 = 1 as is_outlier_2021,

        -- 2022 spending
        tot_spndng_2022 as total_spending_2022,
        tot_dsg_unts_2022 as total_dosage_units_2022,
        tot_clms_2022 as total_claims_2022,
        tot_benes_2022 as total_beneficiaries_2022,
        avg_spnd_per_dsg_unt_wghtd_2022 as avg_spending_per_dosage_unit_weighted_2022,
        avg_spnd_per_clm_2022 as avg_spending_per_claim_2022,
        avg_spnd_per_bene_2022 as avg_spending_per_beneficiary_2022,
        outlier_flag_2022 = 1 as is_outlier_2022,

        -- 2023 spending
        tot_spndng_2023 as total_spending_2023,
        tot_dsg_unts_2023 as total_dosage_units_2023,
        tot_clms_2023 as total_claims_2023,
        tot_benes_2023 as total_beneficiaries_2023,
        avg_spnd_per_dsg_unt_wghtd_2023 as avg_spending_per_dosage_unit_weighted_2023,
        avg_spnd_per_clm_2023 as avg_spending_per_claim_2023,
        avg_spnd_per_bene_2023 as avg_spending_per_beneficiary_2023,
        outlier_flag_2023 = 1 as is_outlier_2023,

        -- 2024 spending
        tot_spndng_2024 as total_spending_2024,
        tot_dsg_unts_2024 as total_dosage_units_2024,
        tot_clms_2024 as total_claims_2024,
        tot_benes_2024 as total_beneficiaries_2024,
        avg_spnd_per_dsg_unt_wghtd_2024 as avg_spending_per_dosage_unit_weighted_2024,
        avg_spnd_per_clm_2024 as avg_spending_per_claim_2024,
        avg_spnd_per_bene_2024 as avg_spending_per_beneficiary_2024,
        outlier_flag_2024 = 1 as is_outlier_2024,

        -- period-over-period change
        chg_avg_spnd_per_dsg_unt_23_24 as change_avg_spending_per_dosage_unit_2023_2024,
        cagr_avg_spnd_per_dsg_unt_20_24 as cagr_avg_spending_per_dosage_unit_2020_2024

    from source

)

select * from renamed
