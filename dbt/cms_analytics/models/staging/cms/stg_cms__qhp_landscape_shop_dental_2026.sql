with source as (

    select * from {{ source('cms_raw', 'cms_qhp_landscape_shop_dental_2026') }}

),

renamed as (

    select
        -- constants
        2026 as plan_year,
        'shop' as market,
        'dental' as product,

        -- identifiers (grain: plan_id × fips_county_code). PY2026
        -- SHOP dental is the thinnest of the four QHP files — 144
        -- rows in WI only — because most FFM states no longer offer
        -- SHOP stand-alone dental.
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

        -- contact / URLs (no drug formulary — dental only)
        nullif(trim("Customer Service Phone Number Local"), '') as customer_service_phone_local,
        nullif(trim("Customer Service Phone Number Toll Free"), '') as customer_service_phone_toll_free,
        nullif(trim("Customer Service Phone Number TTY"), '') as customer_service_phone_tty,
        nullif(trim("Network URL"), '') as network_url,
        nullif(trim("Plan Brochure URL"), '') as plan_brochure_url,
        nullif(trim("Summary of Benefits URL"), '') as summary_of_benefits_url,

        -- coverage indicators (`Covered` / `Not Covered` / `Not
        -- Applicable` per dental service)
        nullif(trim("Routine Dental Services - Adult (Coverage)"), '') as routine_dental_adult_coverage,
        nullif(trim("Basic Dental Care - Adult (Coverage)"), '') as basic_dental_care_adult_coverage,
        nullif(trim("Major Dental Care - Adult (Coverage)"), '') as major_dental_care_adult_coverage,
        nullif(trim("Orthodontia - Adult (Coverage)"), '') as orthodontia_adult_coverage,
        nullif(trim("Dental Check-Up for Children (Coverage)"), '') as dental_checkup_child_coverage,
        nullif(trim("Basic Dental Care - Child (Coverage)"), '') as basic_dental_care_child_coverage,
        nullif(trim("Major Dental Care - Child (Coverage)"), '') as major_dental_care_child_coverage,
        nullif(trim("Orthodontia - Child (Coverage)"), '') as orthodontia_child_coverage,

        -- premium scenarios (37 age/composition cells). Dental
        -- files spell the 3-child brackets as `Couple+3 children` /
        -- `Individual+3 children` (no `or more`); we normalise to
        -- `_3_or_more_children_` so unions align with medical.
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
        try_cast(replace(replace("Couple+3 children, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_3_or_more_children_age_21,
        try_cast(replace(replace("Couple+3 children, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_3_or_more_children_age_30,
        try_cast(replace(replace("Couple+3 children, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_couple_plus_3_or_more_children_age_40,
        try_cast(replace(replace("Couple+3 children, Age 50", '$', ''), ',', '') as decimal(12, 2))
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
        try_cast(replace(replace("Individual+3 children, Age 21", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_21,
        try_cast(replace(replace("Individual+3 children, Age 30", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_30,
        try_cast(replace(replace("Individual+3 children, Age 40", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_40,
        try_cast(replace(replace("Individual+3 children, Age 50", '$', ''), ',', '') as decimal(12, 2))
            as premium_individual_plus_3_or_more_children_age_50,

        -- Standard dental cost-sharing block (no drug block on
        -- dental plans; SHOP dental doesn't get CSR variants).
        try_cast(replace(replace("Dental Deductible - Individual - Standard", '$', ''), ',', '') as decimal(12, 2))
            as dental_deductible_individual_standard,
        try_cast(replace(replace("Dental Deductible - Family - Standard", '$', ''), ',', '') as decimal(12, 2))
            as dental_deductible_family_standard,
        try_cast(replace(replace("Dental Deductible - Family (Per Person) - Standard", '$', ''), ',', '') as decimal(12, 2))
            as dental_deductible_family_per_person_standard,
        try_cast(replace(replace("Dental Maximum Out of Pocket - Individual - Standard", '$', ''), ',', '') as decimal(12, 2))
            as dental_moop_individual_standard,
        try_cast(replace(replace("Dental Maximum Out of Pocket - Family - Standard", '$', ''), ',', '') as decimal(12, 2))
            as dental_moop_family_standard,
        try_cast(
            replace(replace("Dental Maximum Out of Pocket - Family (Per Person) - Standard", '$', ''), ',', '')
            as decimal(12, 2)
        )
            as dental_moop_family_per_person_standard,
        nullif(trim("Routine Dental Services - Adult"), '') as routine_dental_adult_cost_share,
        nullif(trim("Basic Dental Care - Adult"), '') as basic_dental_care_adult_cost_share,
        nullif(trim("Major Dental Care - Adult"), '') as major_dental_care_adult_cost_share,
        nullif(trim("Orthodontia - Adult"), '') as orthodontia_adult_cost_share,
        nullif(trim("Dental Check-Up for Children"), '') as dental_checkup_child_cost_share,
        nullif(trim("Basic Dental Care - Child"), '') as basic_dental_care_child_cost_share,
        nullif(trim("Major Dental Care - Child"), '') as major_dental_care_child_cost_share,
        nullif(trim("Orthodontia - Child"), '') as orthodontia_child_cost_share

        -- section-separator columns (`Premium Rates`, `Standard On
        -- Exchange`) are all-NULL header rows and are excluded.

    from source

)

select * from renamed
