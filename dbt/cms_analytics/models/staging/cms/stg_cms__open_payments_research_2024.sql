with source as (

    select * from {{ source('cms_raw', 'cms_open_payments_research_2024') }}

),

renamed as (

    select
        -- record identifier — one row per research payment record. The
        -- research file is broader than covered-recipient physicians:
        -- 80% of 2024 rows are payments to Non-covered Recipient Entities
        -- (clinical trial sites, contract research organizations); 16%
        -- to Covered Recipient Teaching Hospitals; only ~3.7%
        -- (Covered_Recipient_NPI populated) go to an identifiable
        -- individual clinician. Consumers doing NPI-level rollups must
        -- filter on `covered_recipient_npi is not null`.
        -- Pascal-case source identifiers get explicit snake_case
        -- aliases so the exposed view matches the yml's stated
        -- convention. Quoted because DuckDB preserves the source case
        -- for unaliased columns, and sqlfluff's AL09 (self-alias)
        -- treats an unquoted `record_id as record_id` as a self-alias
        -- rather than the case-change it actually is.
        "Record_ID" as record_id, -- noqa: RF06
        "Program_Year" as program_year, -- noqa: RF06
        "Payment_Publication_Date" as payment_publication_date, -- noqa: RF06
        "Date_of_Payment" as date_of_payment, -- noqa: RF06
        nullif(trim(change_type), '') as change_type,

        -- recipient discriminator: one of
        -- - 'Non-covered Recipient Entity' (655,460 rows)
        -- - 'Covered Recipient Teaching Hospital' (131,407)
        -- - 'Covered Recipient Physician' (28,317)
        -- - 'Covered Recipient Non-Physician Practitioner' (1,961)
        -- - 'Non-covered Recipient Individual' (70)
        nullif(trim(covered_recipient_type), '') as covered_recipient_type,

        -- covered-recipient identifiers (physician / non-physician
        -- practitioner). NPI is populated for 30,198 rows in the 2024 file
        -- (both 'Covered Recipient Physician' and 'Covered Recipient
        -- Non-Physician Practitioner' populations); zero-padded to
        -- ten-digit text when present.
        "Covered_Recipient_Profile_ID" as covered_recipient_profile_id, -- noqa: RF06
        case
            when covered_recipient_npi is null then null
            else lpad(cast(covered_recipient_npi as varchar), 10, '0')
        end as covered_recipient_npi,
        nullif(trim(covered_recipient_first_name), '') as covered_recipient_first_name,
        nullif(trim(covered_recipient_middle_name), '') as covered_recipient_middle_name,
        nullif(trim(covered_recipient_last_name), '') as covered_recipient_last_name,
        nullif(trim(covered_recipient_name_suffix), '') as covered_recipient_name_suffix,
        -- Covered Recipient can carry up to 6 primary types / specialties;
        -- the 2nd–6th columns are extremely sparse. Expose the primary
        -- (position-1) attributes for at-a-glance filtering and leave the
        -- rest raw for the (rare) analyst who needs multi-taxonomy detail.
        nullif(trim(covered_recipient_primary_type_1), '') as covered_recipient_primary_type,
        nullif(trim(covered_recipient_specialty_1), '') as covered_recipient_specialty,

        -- non-covered-recipient entity name (the trial site / CRO /
        -- university) — only populated for Non-covered Recipient Entity
        -- and Non-covered Recipient Individual rows.
        nullif(trim(noncovered_recipient_entity_name), '') as noncovered_recipient_entity_name,

        -- teaching-hospital identifiers — populated for the
        -- 'Covered Recipient Teaching Hospital' variant.
        nullif(trim(teaching_hospital_ccn), '') as teaching_hospital_ccn,
        "Teaching_Hospital_ID" as teaching_hospital_id, -- noqa: RF06
        nullif(trim(teaching_hospital_name), '') as teaching_hospital_name,

        -- Principal Investigator #1 identifiers. The file publishes up to
        -- 5 PIs per record but slots 2–5 are extremely sparse (2024:
        -- PI1 782,718 / PI2 2,181 / PI3 362 / PI4 122 / PI5 86 populated
        -- NPIs). We expose only PI#1 as first-class staging columns
        -- (npi + name + primary_type + specialty); analyses that need
        -- multi-PI detail can go back to the raw source. PI NPIs are
        -- zero-padded ten-digit text when present.
        principal_investigator_1_profile_id as principal_investigator_profile_id,
        case
            when principal_investigator_1_npi is null then null
            else lpad(cast(principal_investigator_1_npi as varchar), 10, '0')
        end as principal_investigator_npi,
        nullif(trim(principal_investigator_1_first_name), '')
            as principal_investigator_first_name,
        nullif(trim(principal_investigator_1_last_name), '')
            as principal_investigator_last_name,
        nullif(trim(principal_investigator_1_primary_type_1), '')
            as principal_investigator_primary_type,
        nullif(trim(principal_investigator_1_specialty_1), '')
            as principal_investigator_specialty,
        nullif(trim(principal_investigator_1_state), '') as principal_investigator_state,

        -- recipient business address (a single US address per row; the
        -- 2024 file is overwhelmingly domestic). Zip is `cast(... as
        -- varchar)` defensively — the parquet load pins it to VARCHAR
        -- via a dtype override, but a future re-materialization could
        -- autodetect BIGINT and break the trim() below.
        nullif(trim(recipient_city), '') as recipient_city,
        nullif(trim(recipient_state), '') as recipient_state,
        nullif(trim(cast(recipient_zip_code as varchar)), '') as recipient_zip,
        nullif(trim(recipient_country), '') as recipient_country,

        -- paying manufacturer / GPO
        nullif(trim(submitting_applicable_manufacturer_or_applicable_gpo_name), '')
            as submitting_manufacturer_or_gpo_name,
        applicable_manufacturer_or_applicable_gpo_making_payment_id
            as paying_manufacturer_or_gpo_id,
        nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_name), '')
            as paying_manufacturer_or_gpo_name,
        nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_state), '')
            as paying_manufacturer_or_gpo_state,
        nullif(trim(applicable_manufacturer_or_applicable_gpo_making_payment_country), '')
            as paying_manufacturer_or_gpo_country,

        -- payment amount and form
        total_amount_of_payment_usdollars as total_amount_of_payment_usd,
        nullif(trim(form_of_payment_or_transfer_of_value), '')
            as form_of_payment,

        -- related-product indicator. Boolean: TRUE when the payment is
        -- tied to at least one named drug / device / biological.
        related_product_indicator as is_related_to_product,

        -- Position-1 product-related columns. Each record can associate up
        -- to 5 covered / non-covered products (each with an
        -- indicator, category, name, NDC, PDI); like PI slots 2–5 the
        -- 2nd–5th product columns are very sparse. Expose only slot 1
        -- for analysis-friendly access; the other four positions remain
        -- in the raw source for deeper drill-in.
        nullif(trim(covered_or_noncovered_indicator_1), '') as product_covered_or_noncovered,
        nullif(trim(indicate_drug_or_biological_or_device_or_medical_supply_1), '')
            as product_category,
        nullif(trim(product_category_or_therapeutic_area_1), '')
            as product_therapeutic_area,
        nullif(trim(name_of_drug_or_biological_or_device_or_medical_supply_1), '')
            as product_name,
        nullif(trim(associated_drug_or_biological_ndc_1), '') as product_ndc,

        -- study attributes
        nullif(trim(name_of_study), '') as name_of_study,
        nullif(trim(clinicaltrials_gov_identifier), '') as clinicaltrials_gov_identifier,
        nullif(trim(research_information_link), '') as research_information_link,
        nullif(trim(context_of_research), '') as context_of_research,

        -- flags
        preclinical_research_indicator as is_preclinical_research,
        delay_in_publication_indicator as is_delayed_publication,
        dispute_status_for_publication as is_dispute_status_for_publication

    from source

)

select * from renamed
