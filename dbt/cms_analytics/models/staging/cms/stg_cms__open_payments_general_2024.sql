with source as (

    select * from {{ source('cms_raw', 'cms_open_payments_general_2024') }}

),

renamed as (

    select
        -- record identifier — one row per general-payment record.
        -- 15,498,687 rows in the 2024 file, all with a distinct
        -- `record_id`. Unlike research, the general file has only
        -- three covered_recipient_type variants: physician
        -- (9,965,643), non-physician practitioner (5,495,656),
        -- teaching hospital (37,388) — no non-covered-recipient
        -- entities. `covered_recipient_npi` is populated on 99.7% of
        -- rows (15,447,409 of 15,498,687) — the ~51K nulls are the
        -- 37,388 teaching-hospital rows plus a small tail of
        -- physician / NPP rows whose NPI is missing from the source
        -- filing. Downstream NPI-level rollups filter on
        -- `covered_recipient_npi is not null`.
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

        -- recipient discriminator
        nullif(trim(covered_recipient_type), '') as covered_recipient_type,

        -- covered-recipient identifiers. NPI is zero-padded to
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

        -- teaching-hospital identifiers — populated only for the
        -- `Covered Recipient Teaching Hospital` variant (37,388 rows).
        nullif(trim(teaching_hospital_ccn), '') as teaching_hospital_ccn,
        "Teaching_Hospital_ID" as teaching_hospital_id, -- noqa: RF06
        nullif(trim(teaching_hospital_name), '') as teaching_hospital_name,

        -- recipient business address (single US address per row; the
        -- non-US province / postal-code columns exist in the raw file
        -- for the tiny international tail and are kept as-is). Zip and
        -- postal code are `cast(... as varchar)` defensively — the
        -- current parquet load pins them to VARCHAR via a dtype
        -- override, but a future re-materialization could autodetect
        -- BIGINT for the mostly-numeric zip column and break the
        -- trim() below with a BinderException.
        nullif(trim(recipient_primary_business_street_address_line1), '')
            as recipient_street_address_1,
        nullif(trim(recipient_primary_business_street_address_line2), '')
            as recipient_street_address_2,
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
        number_of_payments_included_in_total_amount as number_of_payments,
        nullif(trim(form_of_payment_or_transfer_of_value), '') as form_of_payment,
        -- nature-of-payment is the primary categorical attribute for
        -- filtering general payments. 16 values in 2024; Food and
        -- Beverage dominates (91.5%), followed by Travel and Lodging
        -- (3.9%) and Consulting Fee (1.2%).
        nullif(trim(nature_of_payment_or_transfer_of_value), '') as nature_of_payment,

        -- travel context (populated only for 'Travel and Lodging' nature)
        nullif(trim(city_of_travel), '') as travel_city,
        nullif(trim(state_of_travel), '') as travel_state,
        nullif(trim(country_of_travel), '') as travel_country,

        -- third-party-payment routing (payments assigned to a third
        -- party at the recipient's request). 15.36M `No Third Party
        -- Payment` / 109K `Entity` / 33K `Individual`.
        nullif(trim(third_party_payment_recipient_indicator), '')
            as third_party_payment_recipient_indicator,
        nullif(trim(name_of_third_party_entity_receiving_payment_or_transfer_of_value), '')
            as third_party_entity_name,

        -- boolean flags
        physician_ownership_indicator as is_physician_ownership,
        charity_indicator as is_charity,
        third_party_equals_covered_recipient_indicator as is_third_party_equals_covered_recipient,
        delay_in_publication_indicator as is_delayed_publication,
        dispute_status_for_publication as is_dispute_status_for_publication,
        related_product_indicator as is_related_to_product,

        -- free-text context (payer-supplied narrative). Kept raw.
        nullif(trim(contextual_information), '') as contextual_information,

        -- Position-1 product-related columns. Each record can associate up
        -- to 5 covered / non-covered products; slot 1 is populated on
        -- 94% of rows (14.5M), slot 2 on 18%, slots 3–5 on <5%. Expose
        -- only slot 1 for analysis-friendly access; the remaining four
        -- positions stay in the raw source for deeper drill-in.
        nullif(trim(covered_or_noncovered_indicator_1), '') as product_covered_or_noncovered,
        nullif(trim(indicate_drug_or_biological_or_device_or_medical_supply_1), '')
            as product_category,
        nullif(trim(product_category_or_therapeutic_area_1), '')
            as product_therapeutic_area,
        nullif(trim(name_of_drug_or_biological_or_device_or_medical_supply_1), '')
            as product_name,
        nullif(trim(associated_drug_or_biological_ndc_1), '') as product_ndc,
        nullif(trim(associated_device_or_medical_supply_pdi_1), '') as product_pdi

    from source

)

select * from renamed
