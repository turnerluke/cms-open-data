with source as (

    select * from {{ source('cms_raw', 'cms_medicare_part_d_prescribers_by_provider') }}

),

renamed as (

    select
        -- identifiers (one row per prescriber NPI)
        lpad(cast(prscrbr_npi as varchar), 10, '0') as npi,
        trim(prscrbr_last_org_name) as prescriber_last_org_name,
        nullif(trim(prscrbr_first_name), '') as prescriber_first_name,
        nullif(trim(prscrbr_mi), '') as prescriber_middle_initial,
        nullif(trim(prscrbr_crdntls), '') as prescriber_credentials,
        -- entity code: 'I' individual (~1.4M rows), 'O' organization (2 rows)
        trim(prscrbr_ent_cd) as entity_code,

        -- address
        nullif(trim(prscrbr_st1), '') as street_address_1,
        nullif(trim(prscrbr_st2), '') as street_address_2,
        nullif(trim(prscrbr_city), '') as city,
        trim(prscrbr_state_abrvtn) as state,
        nullif(trim(prscrbr_state_fips), '') as state_fips,
        nullif(trim(prscrbr_zip5), '') as zip5,
        -- RUCA code carries meaningful decimal subcodes like 4.1
        prscrbr_ruca as ruca_code,
        nullif(trim(prscrbr_ruca_desc), '') as ruca_description,
        trim(prscrbr_cntry) as country,

        -- prescriber attributes
        nullif(trim(prscrbr_type), '') as prescriber_type,
        -- 'Claim-Specialty' (most common on the prescriber's claims),
        -- 'NPPES-Specialty' or 'NPPES-Taxonomy' (NPPES fallbacks)
        nullif(trim(prscrbr_type_src), '') as prescriber_type_source,

        -- overall Part D utilization and cost totals (never suppressed;
        -- CMS drops NPIs with 10 or fewer total claims from the file
        -- outright rather than suppressing in place)
        tot_clms as total_claims,
        tot_30day_fills as total_30day_fills,
        tot_drug_cst as total_drug_cost,
        tot_day_suply as total_day_supply,
        -- `total_beneficiaries` is separately suppressed (blank → NULL)
        -- when the count is 1–10; ~10% of rows null. No explicit flag
        -- column: total_beneficiaries is null iff CMS suppressed it.
        tot_benes as total_beneficiaries,

        -- age-65-and-over subset. The three-valued suppression flag
        -- (`*` below-threshold, `#` counter-suppressed, NULL disclosed)
        -- pairs 1:1 with all four ge65 measure columns being NULL, and
        -- ge65_beneficiary_suppression_flag pairs 1:1 with
        -- ge65_total_beneficiaries. See the model-level paired-null
        -- expression tests.
        nullif(trim(ge65_sprsn_flag), '') as ge65_suppression_flag,
        ge65_tot_clms as ge65_total_claims,
        ge65_tot_30day_fills as ge65_total_30day_fills,
        ge65_tot_drug_cst as ge65_total_drug_cost,
        ge65_tot_day_suply as ge65_total_day_supply,
        nullif(trim(ge65_bene_sprsn_flag), '') as ge65_beneficiary_suppression_flag,
        ge65_tot_benes as ge65_total_beneficiaries,

        -- brand / generic / other-drug splits, each with its own flag
        nullif(trim(brnd_sprsn_flag), '') as brand_suppression_flag,
        brnd_tot_clms as brand_total_claims,
        brnd_tot_drug_cst as brand_total_drug_cost,
        nullif(trim(gnrc_sprsn_flag), '') as generic_suppression_flag,
        gnrc_tot_clms as generic_total_claims,
        gnrc_tot_drug_cst as generic_total_drug_cost,
        nullif(trim(othr_sprsn_flag), '') as other_suppression_flag,
        othr_tot_clms as other_total_claims,
        othr_tot_drug_cst as other_total_drug_cost,

        -- Medicare-Advantage-Part-D vs stand-alone-PDP splits
        nullif(trim(mapd_sprsn_flag), '') as mapd_suppression_flag,
        mapd_tot_clms as mapd_total_claims,
        mapd_tot_drug_cst as mapd_total_drug_cost,
        nullif(trim(pdp_sprsn_flag), '') as pdp_suppression_flag,
        pdp_tot_clms as pdp_total_claims,
        pdp_tot_drug_cst as pdp_total_drug_cost,

        -- Low-Income-Subsidy vs non-LIS beneficiary splits
        nullif(trim(lis_sprsn_flag), '') as lis_suppression_flag,
        lis_tot_clms as lis_total_claims,
        lis_drug_cst as lis_total_drug_cost,
        nullif(trim(nonlis_sprsn_flag), '') as nonlis_suppression_flag,
        nonlis_tot_clms as nonlis_total_claims,
        nonlis_drug_cst as nonlis_total_drug_cost,

        -- opioid totals; unlike the splits above these columns share no
        -- named suppression flag — the measure columns are NULL directly
        -- when CMS suppresses. `opioid_prescriber_rate` is derived from
        -- opioid claims and shows the same NULL pattern as
        -- `opioid_total_claims`. `opioid_la_prescriber_rate` is
        -- additionally NULL when the prescriber has no long-acting
        -- opioid claims at all.
        opioid_tot_clms as opioid_total_claims,
        opioid_tot_drug_cst as opioid_total_drug_cost,
        opioid_tot_suply as opioid_total_day_supply,
        opioid_tot_benes as opioid_total_beneficiaries,
        opioid_prscrbr_rate as opioid_prescriber_rate,
        opioid_la_tot_clms as opioid_la_total_claims,
        opioid_la_tot_drug_cst as opioid_la_total_drug_cost,
        opioid_la_tot_suply as opioid_la_total_day_supply,
        opioid_la_tot_benes as opioid_la_total_beneficiaries,
        opioid_la_prscrbr_rate as opioid_la_prescriber_rate,

        -- antibiotic totals; same "measure NULL means suppressed" scheme
        antbtc_tot_clms as antibiotic_total_claims,
        antbtc_tot_drug_cst as antibiotic_total_drug_cost,
        antbtc_tot_benes as antibiotic_total_beneficiaries,

        -- antipsychotic totals for age-65-and-over. Two suppression
        -- flags with the same `*`/`#`/NULL semantics; NB the raw column
        -- for the beneficiary flag is misspelled `Suprsn` in CMS's file.
        nullif(trim(antpsyct_ge65_sprsn_flag), '') as antipsychotic_ge65_suppression_flag,
        antpsyct_ge65_tot_clms as antipsychotic_ge65_total_claims,
        antpsyct_ge65_tot_drug_cst as antipsychotic_ge65_total_drug_cost,
        nullif(trim(antpsyct_ge65_bene_suprsn_flag), '') as antipsychotic_ge65_beneficiary_suppression_flag,
        antpsyct_ge65_tot_benes as antipsychotic_ge65_total_beneficiaries,

        -- beneficiary demographics. Averages arrive on nearly every row
        -- (`bene_avg_age` is never null; `bene_avg_risk_score` only null
        -- on 1 row); counts are pairwise-suppressed when the group is
        -- 1–10.
        bene_avg_age as avg_beneficiary_age,
        bene_age_lt_65_cnt as beneficiary_age_lt_65_count,
        bene_age_65_74_cnt as beneficiary_age_65_74_count,
        bene_age_75_84_cnt as beneficiary_age_75_84_count,
        bene_age_gt_84_cnt as beneficiary_age_gt_84_count,
        bene_feml_cnt as beneficiary_female_count,
        bene_male_cnt as beneficiary_male_count,
        bene_race_wht_cnt as beneficiary_race_white_count,
        bene_race_black_cnt as beneficiary_race_black_count,
        bene_race_api_cnt as beneficiary_race_asian_pacific_islander_count,
        bene_race_hspnc_cnt as beneficiary_race_hispanic_count,
        bene_race_natind_cnt as beneficiary_race_native_american_count,
        bene_race_othr_cnt as beneficiary_race_other_count,
        bene_dual_cnt as beneficiary_dual_count,
        bene_ndual_cnt as beneficiary_nondual_count,

        -- risk
        bene_avg_risk_scre as avg_hcc_risk_score

    from source

)

select * from renamed
