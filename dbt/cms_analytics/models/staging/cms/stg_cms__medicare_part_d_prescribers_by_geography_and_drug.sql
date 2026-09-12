with source as (

    select * from {{ source('cms_raw', 'cms_medicare_part_d_prescribers_by_geography_and_drug') }}

),

renamed as (

    select
        -- geography descriptors. Two levels coexist in the file:
        --   'National' — 3,632 rows, one per brand/generic drug; the
        --     geography code is always NULL and the description is
        --     literally 'National'.
        --   'State' — 114,029 rows across 60 codes (50 states + DC,
        --     Puerto Rico, Virgin Islands, Guam, Northern Mariana
        --     Islands, American Samoa, plus armed-forces / foreign /
        --     unknown pseudo-codes 9A–9E). One State row currently ships
        --     with a NULL geography code and description (Trazodone
        --     Hcl, from the RY26 vintage).
        trim(prscrbr_geo_lvl) as geography_level,
        nullif(trim(prscrbr_geo_cd), '') as geography_code,
        nullif(trim(prscrbr_geo_desc), '') as geography_description,

        -- drug identifiers. Both are never NULL and combine with
        -- geography to form the grain. `brand_name` echoes the generic
        -- for generic-only drugs; `generic_name` is the chemical name.
        trim(brnd_name) as brand_name,
        trim(gnrc_name) as generic_name,

        -- overall utilization and cost totals across all prescribers
        -- rolling up to this geography × drug cell. `total_prescribers`,
        -- `total_claims`, `total_30day_fills`, and `total_drug_cost` are
        -- never NULL. `total_beneficiaries` is suppressed (blank → NULL)
        -- when the count is 1–10; ~19% of rows null. No explicit flag
        -- column — `total_beneficiaries` is null iff suppressed.
        tot_prscrbrs as total_prescribers,
        tot_clms as total_claims,
        tot_30day_fills as total_30day_fills,
        tot_drug_cst as total_drug_cost,
        tot_benes as total_beneficiaries,

        -- age-65-and-over subset with the standard three-valued CMS
        -- suppression flags. `ge65_suppression_flag` pairs 1:1 with
        -- NULLs across `ge65_total_claims`, `ge65_total_30day_fills`,
        -- and `ge65_total_drug_cost`; `ge65_beneficiary_suppression_flag`
        -- pairs 1:1 with `ge65_total_beneficiaries`.
        nullif(trim(ge65_sprsn_flag), '') as ge65_suppression_flag,
        ge65_tot_clms as ge65_total_claims,
        ge65_tot_30day_fills as ge65_total_30day_fills,
        ge65_tot_drug_cst as ge65_total_drug_cost,
        nullif(trim(ge65_bene_sprsn_flag), '') as ge65_beneficiary_suppression_flag,
        ge65_tot_benes as ge65_total_beneficiaries,

        -- average beneficiary cost-share by Low-Income-Subsidy status,
        -- in dollars. Never NULL.
        lis_bene_cst_shr as lis_beneficiary_cost_share,
        nonlis_bene_cst_shr as nonlis_beneficiary_cost_share,

        -- drug-class flags ('Y' / 'N'). Never NULL; boolean-cast so
        -- downstream marts don't have to compare strings.
        opioid_drug_flag = 'Y' as is_opioid,
        opioid_la_drug_flag = 'Y' as is_long_acting_opioid,
        antbtc_drug_flag = 'Y' as is_antibiotic,
        antpsyct_drug_flag = 'Y' as is_antipsychotic

    from source

)

select * from renamed
