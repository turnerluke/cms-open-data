with source as (

    select * from {{ source('cms_raw', 'cms_open_payments_ownership_2024') }}

),

renamed as (

    select
        -- record identifier (surrogate PK for a single ownership
        -- interest disclosure). Pascal-case source identifiers get
        -- explicit snake_case aliases so the exposed view matches the
        -- yml's stated convention. Quoted because DuckDB preserves the
        -- source case for unaliased columns, and sqlfluff's AL09
        -- (self-alias) treats an unquoted `record_id as record_id` as
        -- a self-alias rather than the case-change it actually is.
        "Record_ID" as record_id, -- noqa: RF06
        "Program_Year" as program_year, -- noqa: RF06
        "Payment_Publication_Date" as payment_publication_date, -- noqa: RF06

        -- change type marker on the row (NEW / UNCHANGED / CHANGED / ADD)
        nullif(trim(change_type), '') as change_type,

        -- physician identifiers. Ownership rows always describe a physician
        -- (or an immediate family member's interest held on the physician's
        -- behalf) — there is no "teaching hospital" or non-covered entity
        -- variant on this file. NPI is populated for 4,832 / 4,834 rows in
        -- the 2024 file (2 nulls). Zero-padded to ten-digit text when
        -- present so it conforms with the rest of the warehouse.
        "Physician_Profile_ID" as physician_profile_id, -- noqa: RF06
        case
            when physician_npi is null then null
            else lpad(cast(physician_npi as varchar), 10, '0')
        end as physician_npi,
        nullif(trim(physician_first_name), '') as physician_first_name,
        nullif(trim(physician_middle_name), '') as physician_middle_name,
        nullif(trim(physician_last_name), '') as physician_last_name,
        nullif(trim(physician_name_suffix), '') as physician_name_suffix,
        nullif(trim(physician_primary_type), '') as physician_primary_type,
        nullif(trim(physician_specialty), '') as physician_specialty,

        -- who holds the interest: 'Physician Covered Recipient' (4,613 rows
        -- in the 2024 file) vs 'Immediate family member' (221 rows).
        nullif(trim(interest_held_by_physician_or_an_immediate_family_member), '')
            as interest_held_by,

        -- recipient address (single US address per row; the 2024 file is
        -- 100% domestic — no populated province / postal_code / non-US
        -- country rows — so those columns are dropped). Zip is `cast(...
        -- as varchar)` defensively — the parquet load pins it to VARCHAR
        -- via a dtype override, but a future re-materialization could
        -- autodetect BIGINT and break the trim() below.
        nullif(trim(recipient_primary_business_street_address_line1), '')
            as recipient_street_address_1,
        nullif(trim(recipient_primary_business_street_address_line2), '')
            as recipient_street_address_2,
        nullif(trim(recipient_city), '') as recipient_city,
        nullif(trim(recipient_state), '') as recipient_state,
        nullif(trim(cast(recipient_zip_code as varchar)), '') as recipient_zip,
        nullif(trim(recipient_country), '') as recipient_country,

        -- paying entity
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

        -- financial terms
        total_amount_invested_usdollars as total_amount_invested_usd,
        value_of_interest as value_of_interest_usd,
        nullif(trim(terms_of_interest), '') as terms_of_interest,

        -- publication dispute flag: raw is boolean (all FALSE in the 2024
        -- file). Kept as-is; no rows are excluded from publication so
        -- there is no downstream filter.
        dispute_status_for_publication as is_dispute_status_for_publication

    from source

)

select * from renamed
