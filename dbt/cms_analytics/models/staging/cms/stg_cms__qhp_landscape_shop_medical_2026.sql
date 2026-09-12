with source as (

    select * from {{ source('cms_raw', 'cms_qhp_landscape_shop_medical_2026') }}

),

renamed as (

    select
        -- constants
        2026 as plan_year,
        'shop' as market,
        'medical' as product,

        -- identifiers (grain: plan_id × fips_county_code). PY2026
        -- SHOP medical is thin — 3,001 rows across 4 states (AL,
        -- MT, NH, WI) — because most FFM states no longer offer
        -- SHOP medical.
        trim("State Code") as state_code,
        trim("FIPS County Code") as fips_county_code,
        trim("County Name") as county_name,
        trim("Metal Level") as metal_level,
        trim("Issuer Name") as issuer_name,
        trim("HIOS Issuer ID") as hios_issuer_id,
        trim("Plan ID (Standard Component)") as plan_id,
        trim("Plan Marketing Name") as plan_marketing_name,
        trim("Plan Type") as plan_type,
        trim("Rating Area") as rating_area,
        nullif(trim("Child Only Offering"), '') as child_only_offering,
        -- HIOS vs SERFF certification-system provenance
        trim(source) as source_system,

        -- contact / URLs
        nullif(trim("Customer Service Phone Number Local"), '') as customer_service_phone_local,
        nullif(trim("Customer Service Phone Number Toll Free"), '') as customer_service_phone_toll_free,
        nullif(trim("Customer Service Phone Number TTY"), '') as customer_service_phone_tty,
        nullif(trim("Network URL"), '') as network_url,
        nullif(trim("Plan Brochure URL"), '') as plan_brochure_url,
        nullif(trim("Summary of Benefits URL"), '') as summary_of_benefits_url,
        nullif(trim("Drug Formulary URL"), '') as drug_formulary_url,

        -- adult / pediatric dental coverage indicators (`X` when
        -- covered by this medical plan, else NULL)
        nullif(trim("Adult Dental"), '') as adult_dental_indicator,
        nullif(trim("Child Dental"), '') as child_dental_indicator,

        -- premium scenarios (37 age/composition cells). Money
        -- strings (`$NNN.NN` / `$N,NNN.NN`) → decimal.
        try_cast(replace(replace("Premium Child Age 0-14", '$', ''), ',', '') as decimal(12, 2))
            as premium_child_age_0_14,
        try_cast(replace(replace("Premium Child Age 18", '$', ''), ',', '') as decimal(12, 2))
            as premium_child_age_18,
        try_cast(replace(replace("Premium Adult Individual Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_adult_individual_age_21,
        try_cast(replace(replace("Premium Adult Individual Age 27", '$', ''), ',', '') as decimal(12, 2))
            as premium_adult_individual_age_27,
        try_cast(replace(replace("Premium Adult Individual Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_adult_individual_age_30,
        try_cast(replace(replace("Premium Adult Individual Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_adult_individual_age_40,
        try_cast(replace(replace("Premium Adult Individual Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_adult_individual_age_50,
        try_cast(replace(replace("Premium Adult Individual Age 60", '$', ''), ',', '') as decimal(12, 2))
            as premium_adult_individual_age_60,
        try_cast(replace(replace("Premium Couple 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_age_21,
        try_cast(replace(replace("Premium Couple 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_age_30,
        try_cast(replace(replace("Premium Couple 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_age_40,
        try_cast(replace(replace("Premium Couple 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_age_50,
        try_cast(replace(replace("Premium Couple 60", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_age_60,
        try_cast(replace(replace("Couple+1 child, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_1_child_age_21,
        try_cast(replace(replace("Couple+1 child, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_1_child_age_30,
        try_cast(replace(replace("Couple+1 child, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_1_child_age_40,
        try_cast(replace(replace("Couple+1 child, Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_1_child_age_50,
        try_cast(replace(replace("Couple+2 children, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_2_children_age_21,
        try_cast(replace(replace("Couple+2 children, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_2_children_age_30,
        try_cast(replace(replace("Couple+2 children, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_2_children_age_40,
        try_cast(replace(replace("Couple+2 children, Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_2_children_age_50,
        try_cast(replace(replace("Couple+3 or more Children, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_3_or_more_children_age_21,
        try_cast(replace(replace("Couple+3 or more Children, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_3_or_more_children_age_30,
        try_cast(replace(replace("Couple+3 or more Children, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_3_or_more_children_age_40,
        try_cast(replace(replace("Couple+3 or more Children, Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_3_or_more_children_age_50,
        try_cast(replace(replace("Individual+1 child, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_1_child_age_21,
        try_cast(replace(replace("Individual+1 child, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_1_child_age_30,
        try_cast(replace(replace("Individual+1 child, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_1_child_age_40,
        try_cast(replace(replace("Individual+1 child, Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_1_child_age_50,
        try_cast(replace(replace("Individual+2 children, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_2_children_age_21,
        try_cast(replace(replace("Individual+2 children, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_2_children_age_30,
        try_cast(replace(replace("Individual+2 children, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_2_children_age_40,
        try_cast(replace(replace("Individual+2 children, Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_2_children_age_50,
        try_cast(replace(replace("Individual+3 or more children, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_21,
        try_cast(replace(replace("Individual+3 or more children, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_30,
        try_cast(replace(replace("Individual+3 or more children, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_40,
        try_cast(replace(replace("Individual+3 or more children, Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_50,

        -- Standard cost-sharing block. SHOP does not carry the 73/
        -- 87/94 percent CSR variants (CSRs are individual-market
        -- only) or the EHB-percent column. Copay/coinsurance
        -- columns stay as trimmed text since they mix `$30`, `20%
        -- Coinsurance after deductible`, and `No Charge` values.
        try_cast(replace(replace("Medical Deductible - Individual - Standard", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_individual_standard,
        try_cast(replace(replace("Drug Deductible - Individual - Standard", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_individual_standard,
        try_cast(replace(replace("Medical Deductible - Family - Standard", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_standard,
        try_cast(replace(replace("Drug Deductible - Family - Standard", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_standard,
        try_cast(replace(replace("Medical Deductible - Family (Per Person) - Standard", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_per_person_standard,
        try_cast(replace(replace("Drug Deductible - Family (Per Person) - Standard", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_per_person_standard,
        try_cast(replace(replace("Medical Maximum Out Of Pocket - Individual - Standard", '$', ''), ',', '') as decimal(12, 2))
            as medical_moop_individual_standard,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - Individual - Standard", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_individual_standard,
        try_cast(replace(replace("Medical Maximum Out Of Pocket - Family - Standard", '$', ''), ',', '') as decimal(12, 2))
            as medical_moop_family_standard,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - Family - Standard", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_family_standard,
        try_cast(
            replace(replace("Medical Maximum Out Of Pocket - Family (Per Person) - Standard", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as medical_moop_family_per_person_standard,
        try_cast(
            replace(replace("Drug Maximum Out Of Pocket - Family (Per Person) - Standard", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as drug_moop_family_per_person_standard,
        nullif(trim("Primary Care Physician - Standard"), '') as primary_care_physician_standard,
        nullif(trim("Specialist - Standard"), '') as specialist_standard,
        nullif(trim("Emergency Room - Standard"), '') as emergency_room_standard,
        nullif(trim("Inpatient Facility - Standard"), '') as inpatient_facility_standard,
        nullif(trim("Inpatient Physician - Standard"), '') as inpatient_physician_standard,
        nullif(trim("Generic Drugs - Standard"), '') as generic_drugs_standard,
        nullif(trim("Preferred Brand Drugs - Standard"), '') as preferred_brand_drugs_standard,
        nullif(trim("Non-preferred Brand Drugs - Standard"), '') as non_preferred_brand_drugs_standard,
        nullif(trim("Specialty Drugs - Standard"), '') as specialty_drugs_standard,
        -- Integrated pharmacy-benefit flag. Every drug-MOOP value
        -- on PY2026 SHOP medical is the sentinel `Included in
        -- Medical` (drug spend accrues to the medical MOOP rather
        -- than a separate pharmacy accumulator) — a real product-
        -- design signal, not bad data. The numeric try_cast MOOP
        -- columns above silently null those rows, so this boolean
        -- preserves the signal. Sourced from Drug MOOP -
        -- Individual; Drug Deductible carries the same sentinel on
        -- ~72% of rows and disagrees with MOOP on the ~28% that
        -- are numeric — we treat MOOP as the canonical flag.
        "Drug Maximum Out Of Pocket - Individual - Standard" = 'Included in Medical'
            as drug_benefits_integrated_standard

    -- section-separator columns (`Premium Scenarios`, `Standard
    -- Plan Cost Sharing`) are all-NULL header rows and are
    -- intentionally excluded.

    from source

)

select * from renamed
