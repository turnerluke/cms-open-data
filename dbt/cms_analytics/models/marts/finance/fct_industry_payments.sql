with staged as (

    select * from {{ ref('stg_cms__open_payments_general_2024') }}

),

final as (

    select
        -- identifier / grain (one row per general-payment record).
        -- CMS-assigned; unique within the 2024 file (15,498,687 rows,
        -- 15,498,687 distinct `record_id`).
        record_id,
        program_year,

        -- covered-recipient identifiers. `covered_recipient_npi` is
        -- populated for 15,447,409 rows (99.7%) — nulls are the
        -- 37,388 teaching-hospital rows plus a small tail of covered
        -- clinician rows the payer filed without an NPI. The FK to
        -- `dim_clinician` is filtered on `covered_recipient_npi is
        -- not null` so it tests only the population the roster
        -- actually covers — see the yml for the residual-orphan
        -- breakdown.
        covered_recipient_npi,
        covered_recipient_type,
        covered_recipient_primary_type,
        covered_recipient_specialty,
        covered_recipient_profile_id,
        covered_recipient_first_name,
        covered_recipient_last_name,

        -- teaching-hospital identifiers (populated only for
        -- `Covered Recipient Teaching Hospital` rows, 37,388 in 2024)
        teaching_hospital_ccn,
        teaching_hospital_id,
        teaching_hospital_name,

        -- recipient business address
        recipient_city,
        recipient_state,
        recipient_zip,
        recipient_country,

        -- paying manufacturer / GPO
        submitting_manufacturer_or_gpo_name,
        paying_manufacturer_or_gpo_id,
        paying_manufacturer_or_gpo_name,
        paying_manufacturer_or_gpo_state,
        paying_manufacturer_or_gpo_country,

        -- payment amount and vehicle
        total_amount_of_payment_usd,
        number_of_payments,
        form_of_payment,
        -- primary categorical: 16 nature-of-payment categories in
        -- 2024, dominated by Food and Beverage (91.5%)
        nature_of_payment,
        -- Sunshine Act reporting began in program year 2013, so
        -- anything before 2014-01-01 is a data-entry typo. 75 rows
        -- in the 2024 vintage report `0002-11-30` (obvious year-2
        -- typo); null those out here so `date_trunc('year', ...)`
        -- charts don't render a phantom "year 2" bucket. The 2014
        -- floor is generous — the actual first program year covered
        -- by this file is 2024 — but keeps the guard clearly a
        -- typo-filter rather than a policy assertion about which
        -- program years exist in the data.
        case
            when date_of_payment < date '2014-01-01' then null
            else date_of_payment
        end as date_of_payment,
        -- Derived year that consumers can safely bucket on: prefer
        -- the (cleaned) date, fall back to `program_year` when the
        -- date was typo-nulled above. Never null in 2024's data
        -- because every row has a program_year.
        coalesce(
            year(
                case
                    when date_of_payment < date '2014-01-01' then null
                    else date_of_payment
                end
            ),
            program_year
        ) as payment_year,
        payment_publication_date,

        -- travel context (populated only for `Travel and Lodging`)
        travel_city,
        travel_state,
        travel_country,

        -- third-party routing
        third_party_payment_recipient_indicator,
        third_party_entity_name,

        -- Position-1 product-related attributes (slot 1 is populated
        -- on 94% of rows; sparse slots 2–5 remain in the staging
        -- source for deep drill-in)
        is_related_to_product,
        product_covered_or_noncovered,
        product_category,
        product_therapeutic_area,
        product_name,
        product_ndc,

        -- boolean flags kept as-is
        is_physician_ownership,
        is_charity,
        is_third_party_equals_covered_recipient,
        is_delayed_publication,
        is_dispute_status_for_publication,

        contextual_information,

        -- snapshot vintage: upstream `modified` date of the source
        -- file. Scalar subquery so a missing sidecar surfaces as a
        -- null (caught by the not_null test) instead of losing rows.
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'open_payments_general_2024'
        ) as as_of

    from staged

)

select * from final
