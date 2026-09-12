with source as (

    select * from {{ source('cms_raw', 'cms_qhp_landscape_individual_medical_2026') }}

),

renamed as (

    select
        -- constants — the grain is one row per plan × county for a
        -- single (plan_year, market, product) tuple; carrying these
        -- forward lets downstream unions across the four QHP files
        -- filter without re-joining
        2026 as plan_year,
        'individual' as market,
        'medical' as product,

        -- identifiers (grain: plan_id × fips_county_code; 30 FFM
        -- states, no state-based exchanges are in this file)
        trim("State Code") as state_code,
        trim("FIPS County Code") as fips_county_code,
        trim("County Name") as county_name,
        trim("Metal Level") as metal_level,
        trim("Issuer Name") as issuer_name,
        trim("HIOS Issuer ID") as hios_issuer_id,
        trim("Plan ID (Standard Component)") as plan_id,
        trim("Plan Marketing Name") as plan_marketing_name,
        -- `Design 1|2|3` or `Not Applicable`; only present on the
        -- individual-medical file (SHOP and dental files don't carry
        -- standardized plan options)
        nullif(trim("Standardized Plan Option"), '') as standardized_plan_option,
        trim("Plan Type") as plan_type,
        trim("Rating Area") as rating_area,
        nullif(trim("Child Only Offering"), '') as child_only_offering,
        -- HIOS vs SERFF — provenance of the plan certification, not
        -- data quality
        trim(source) as source_system,

        -- contact / URLs
        nullif(trim("Customer Service Phone Number Local"), '') as customer_service_phone_local,
        nullif(trim("Customer Service Phone Number Toll Free"), '') as customer_service_phone_toll_free,
        nullif(trim("Customer Service Phone Number TTY"), '') as customer_service_phone_tty,
        nullif(trim("Network URL"), '') as network_url,
        nullif(trim("Plan Brochure URL"), '') as plan_brochure_url,
        nullif(trim("Summary of Benefits URL"), '') as summary_of_benefits_url,
        nullif(trim("Drug Formulary URL"), '') as drug_formulary_url,

        -- pediatric / adult dental indicator — sparsely populated
        -- (`X` when covered, else NULL)
        nullif(trim("Adult Dental"), '') as adult_dental_indicator,
        nullif(trim("Child Dental"), '') as child_dental_indicator,

        -- EHB share of premium, stored as a `NN.NN%` string; strip
        -- the trailing `%` and cast to a percent-scale decimal
        -- (94.69–100.00 in the current vintage, so keeping it on the
        -- percent scale keeps values human-legible without a x100)
        try_cast(replace(nullif(trim("EHB Percent of Total Premium"), ''), '%', '') as decimal(6, 3))
            as ehb_percent_of_total_premium,

        -- premium scenarios (37 age/composition cells). Values arrive
        -- as `$NNN.NN` or `$N,NNN.NN` strings; strip `$`/`,` and cast
        -- to a two-decimal money type. try_cast keeps the build
        -- forward-compatible if CMS ever ships a blank cell.
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

        -- Standard cost-sharing block. Deductibles and MOOPs cast to
        -- money; copay/coinsurance columns stay as trimmed text
        -- because they mix formats (`$30`, `20% Coinsurance after
        -- deductible`, `$25 Copay with deductible and 20%
        -- Coinsurance after deductible`, `No Charge`) that don't
        -- parse to a single scalar.
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
        -- Integrated pharmacy-benefit flag for the Standard cost-
        -- sharing variant. Every drug-MOOP column on this file
        -- carries the sentinel `Included in Medical` (drug spend
        -- accrues to the medical deductible/MOOP rather than a
        -- separate pharmacy accumulator) — a real product-design
        -- signal, not bad data. The numeric try_cast columns above
        -- silently null those rows, so this boolean preserves the
        -- signal. Sourced from Drug MOOP - Individual (100%
        -- `Included in Medical` across all four cost-sharing
        -- variants in this vintage); Drug Deductible carries the
        -- same sentinel on ~89% of Standard rows and disagrees
        -- with MOOP on the ~11% that are numeric — we treat MOOP
        -- as the canonical integration flag.
        "Drug Maximum Out Of Pocket - Individual - Standard" = 'Included in Medical'
            as drug_benefits_integrated_standard,

        -- 73 Percent Actuarial Value Silver CSR variant. Populated
        -- only for silver-level plans; other rows are NULL.
        try_cast(replace(replace("Medical Deductible - Individual - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_individual_73_percent,
        try_cast(replace(replace("Drug Deductible - Individual - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_individual_73_percent,
        try_cast(replace(replace("Medical Deductible - Family - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_73_percent,
        try_cast(replace(replace("Drug Deductible - Family - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_73_percent,
        try_cast(replace(replace("Medical Deductible - Family (Per Person) - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_per_person_73_percent,
        try_cast(replace(replace("Drug Deductible - Family (Per Person) - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_per_person_73_percent,
        try_cast(
            replace(replace("Medical Maximum Out Of Pocket - Individual - 73 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as medical_moop_individual_73_percent,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - Individual - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_individual_73_percent,
        try_cast(replace(replace("Medical Maximum Out Of Pocket - Family - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_moop_family_73_percent,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - Family - 73 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_family_73_percent,
        try_cast(
            replace(replace("Medical Maximum Out Of Pocket - Family (Per Person) - 73 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as medical_moop_family_per_person_73_percent,
        try_cast(
            replace(replace("Drug Maximum Out Of Pocket - Family (Per Person) - 73 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as drug_moop_family_per_person_73_percent,
        nullif(trim("Primary Care Physician - 73 Percent"), '') as primary_care_physician_73_percent,
        nullif(trim("Specialist - 73 Percent"), '') as specialist_73_percent,
        nullif(trim("Emergency Room - 73 Percent"), '') as emergency_room_73_percent,
        nullif(trim("Inpatient Facility - 73 Percent"), '') as inpatient_facility_73_percent,
        nullif(trim("Inpatient Physician - 73 Percent"), '') as inpatient_physician_73_percent,
        nullif(trim("Generic Drugs - 73 Percent"), '') as generic_drugs_73_percent,
        nullif(trim("Preferred Brand Drugs - 73 Percent"), '') as preferred_brand_drugs_73_percent,
        nullif(trim("Non-preferred Brand Drugs - 73 Percent"), '') as non_preferred_brand_drugs_73_percent,
        nullif(trim("Specialty Drugs - 73 Percent"), '') as specialty_drugs_73_percent,
        -- Integrated pharmacy-benefit flag for the 73-percent CSR
        -- variant. NULL when the row has no CSR block (non-
        -- silver); true when the source drug-MOOP is `Included in
        -- Medical` (100% of populated rows in this vintage).
        case
            when "Drug Maximum Out Of Pocket - Individual - 73 Percent" is null then null
            else "Drug Maximum Out Of Pocket - Individual - 73 Percent" = 'Included in Medical'
        end as drug_benefits_integrated_73_percent,

        -- 87 Percent Actuarial Value Silver CSR variant.
        try_cast(replace(replace("Medical Deductible - Individual - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_individual_87_percent,
        try_cast(replace(replace("Drug Deductible - Individual - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_individual_87_percent,
        try_cast(replace(replace("Medical Deductible - Family - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_87_percent,
        try_cast(replace(replace("Drug Deductible - Family - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_87_percent,
        try_cast(replace(replace("Medical Deductible - Family (Per Person) - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_per_person_87_percent,
        try_cast(replace(replace("Drug Deductible - Family (Per Person) - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_per_person_87_percent,
        try_cast(
            replace(replace("Medical Maximum Out Of Pocket - Individual - 87 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as medical_moop_individual_87_percent,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - Individual - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_individual_87_percent,
        try_cast(replace(replace("Medical Maximum Out Of Pocket - Family - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_moop_family_87_percent,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - Family - 87 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_family_87_percent,
        try_cast(
            replace(replace("Medical Maximum Out Of Pocket - Family (Per Person) - 87 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as medical_moop_family_per_person_87_percent,
        try_cast(
            replace(replace("Drug Maximum Out Of Pocket - Family (Per Person) - 87 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as drug_moop_family_per_person_87_percent,
        nullif(trim("Primary Care Physician - 87 Percent"), '') as primary_care_physician_87_percent,
        nullif(trim("Specialist - 87 Percent"), '') as specialist_87_percent,
        nullif(trim("Emergency Room - 87 Percent"), '') as emergency_room_87_percent,
        nullif(trim("Inpatient Facility - 87 Percent"), '') as inpatient_facility_87_percent,
        nullif(trim("Inpatient Physician - 87 Percent"), '') as inpatient_physician_87_percent,
        nullif(trim("Generic Drugs - 87 Percent"), '') as generic_drugs_87_percent,
        nullif(trim("Preferred Brand Drugs - 87 Percent"), '') as preferred_brand_drugs_87_percent,
        nullif(trim("Non-preferred Brand Drugs - 87 Percent"), '') as non_preferred_brand_drugs_87_percent,
        nullif(trim("Specialty Drugs - 87 Percent"), '') as specialty_drugs_87_percent,
        -- Integrated pharmacy-benefit flag for the 87-percent CSR
        -- variant. NULL for non-silver rows; true when the source
        -- drug-MOOP is `Included in Medical`.
        case
            when "Drug Maximum Out Of Pocket - Individual - 87 Percent" is null then null
            else "Drug Maximum Out Of Pocket - Individual - 87 Percent" = 'Included in Medical'
        end as drug_benefits_integrated_87_percent,

        -- 94 Percent Actuarial Value Silver CSR variant. Note CMS
        -- ships this block with inconsistent header casing —
        -- `Medical Maximum Out Of Pocket -individual - 94 Percent`
        -- (no space, lowercase `individual`), `Drug Maximum Out Of
        -- Pocket - Family  - 94 Percent` (double space) — we quote
        -- the exact strings verbatim to survive.
        try_cast(replace(replace("Medical Deductible - Individual - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_individual_94_percent,
        try_cast(replace(replace("Drug Deductible - Individual - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_individual_94_percent,
        try_cast(replace(replace("Medical Deductible - Family - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_94_percent,
        try_cast(replace(replace("Drug Deductible - Family - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_94_percent,
        try_cast(replace(replace("Medical Deductible - Family (Per Person) - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_deductible_family_per_person_94_percent,
        try_cast(replace(replace("Drug Deductible - Family (Per Person) - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_deductible_family_per_person_94_percent,
        try_cast(replace(replace("Medical Maximum Out Of Pocket -individual - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_moop_individual_94_percent,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - individual - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_individual_94_percent,
        try_cast(replace(replace("Medical Maximum Out Of Pocket - family - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as medical_moop_family_94_percent,
        try_cast(replace(replace("Drug Maximum Out Of Pocket - Family  - 94 Percent", '$', ''), ',', '') as decimal(12, 2))
            as drug_moop_family_94_percent,
        try_cast(
            replace(replace("Medical Maximum Out Of Pocket - Family (Per Person) - 94 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as medical_moop_family_per_person_94_percent,
        try_cast(
            replace(replace("Drug Maximum Out Of Pocket - Family (Per Person) - 94 Percent", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as drug_moop_family_per_person_94_percent,
        nullif(trim("Primary Care Physician - 94 Percent"), '') as primary_care_physician_94_percent,
        nullif(trim("Specialist - 94 Percent"), '') as specialist_94_percent,
        nullif(trim("Emergency Room - 94 Percent"), '') as emergency_room_94_percent,
        nullif(trim("Inpatient Facility - 94 Percent"), '') as inpatient_facility_94_percent,
        nullif(trim("Inpatient Physician - 94 Percent"), '') as inpatient_physician_94_percent,
        nullif(trim("Generic Drugs - 94 Percent"), '') as generic_drugs_94_percent,
        nullif(trim("Preferred Brand Drugs - 94 Percent"), '') as preferred_brand_drugs_94_percent,
        nullif(trim("Non-preferred Brand Drugs - 94 Percent"), '') as non_preferred_brand_drugs_94_percent,
        nullif(trim("Specialty Drugs - 94 Percent"), '') as specialty_drugs_94_percent,
        -- Integrated pharmacy-benefit flag for the 94-percent CSR
        -- variant. Sourced from the CMS-inconsistent-cased column
        -- `Drug Maximum Out Of Pocket - individual - 94 Percent`
        -- (lowercase `individual`) — quoted verbatim.
        case
            when "Drug Maximum Out Of Pocket - individual - 94 Percent" is null then null
            else "Drug Maximum Out Of Pocket - individual - 94 Percent" = 'Included in Medical'
        end as drug_benefits_integrated_94_percent

        -- section-separator columns from the source XLSX (`Premium
        -- Scenarios`, `Standard Plan Cost Sharing`, `73/87/94
        -- Percent Actuarial Value Silver Plan Cost Sharing`) are all
        -- fully NULL header rows and are intentionally excluded.

    from source

)

select * from renamed
