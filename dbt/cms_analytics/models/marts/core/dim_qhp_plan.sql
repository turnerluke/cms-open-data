with individual_medical as (

    select
        plan_id,
        plan_year,
        market,
        product,
        hios_issuer_id,
        issuer_name,
        plan_marketing_name,
        metal_level,
        plan_type,
        child_only_offering,
        source_system,
        standardized_plan_option,
        ehb_percent_of_total_premium,
        drug_benefits_integrated_standard,
        network_url,
        plan_brochure_url,
        summary_of_benefits_url,
        drug_formulary_url,
        customer_service_phone_local,
        customer_service_phone_toll_free,
        customer_service_phone_tty
    from {{ ref('stg_cms__qhp_landscape_individual_medical_2026') }}

),

individual_dental as (

    -- dental files have no CSR/EHB block and no drug formulary; NULL those columns
    -- so the union preserves column parity across the four sources.
    select
        plan_id,
        plan_year,
        market,
        product,
        hios_issuer_id,
        issuer_name,
        plan_marketing_name,
        metal_level,
        plan_type,
        child_only_offering,
        source_system,
        cast(null as varchar) as standardized_plan_option,
        cast(null as decimal(6, 3)) as ehb_percent_of_total_premium,
        cast(null as boolean) as drug_benefits_integrated_standard,
        network_url,
        plan_brochure_url,
        summary_of_benefits_url,
        cast(null as varchar) as drug_formulary_url,
        customer_service_phone_local,
        customer_service_phone_toll_free,
        customer_service_phone_tty
    from {{ ref('stg_cms__qhp_landscape_individual_dental_2026') }}

),

shop_medical as (

    -- SHOP medical carries no `Standardized Plan Option` or `EHB Percent`
    -- columns (CSRs are individual-market only), but keeps the drug-
    -- integration flag and formulary URL.
    select
        plan_id,
        plan_year,
        market,
        product,
        hios_issuer_id,
        issuer_name,
        plan_marketing_name,
        metal_level,
        plan_type,
        child_only_offering,
        source_system,
        cast(null as varchar) as standardized_plan_option,
        cast(null as decimal(6, 3)) as ehb_percent_of_total_premium,
        drug_benefits_integrated_standard,
        network_url,
        plan_brochure_url,
        summary_of_benefits_url,
        drug_formulary_url,
        customer_service_phone_local,
        customer_service_phone_toll_free,
        customer_service_phone_tty
    from {{ ref('stg_cms__qhp_landscape_shop_medical_2026') }}

),

shop_dental as (

    select
        plan_id,
        plan_year,
        market,
        product,
        hios_issuer_id,
        issuer_name,
        plan_marketing_name,
        metal_level,
        plan_type,
        child_only_offering,
        source_system,
        cast(null as varchar) as standardized_plan_option,
        cast(null as decimal(6, 3)) as ehb_percent_of_total_premium,
        cast(null as boolean) as drug_benefits_integrated_standard,
        network_url,
        plan_brochure_url,
        summary_of_benefits_url,
        cast(null as varchar) as drug_formulary_url,
        customer_service_phone_local,
        customer_service_phone_toll_free,
        customer_service_phone_tty
    from {{ ref('stg_cms__qhp_landscape_shop_dental_2026') }}

),

unioned as (

    select * from individual_medical
    union all
    select * from individual_dental
    union all
    select * from shop_medical
    union all
    select * from shop_dental

),

-- Each candidate attribute was verified constant per plan_id across the
-- union (max distinct value per plan_id = 1, zero collisions on every
-- listed column in the PY2026 vintage), so `any_value` is a deterministic
-- collapse — no tie-breaks needed. See the model description.
collapsed as (

    select
        plan_id,
        any_value(plan_year) as plan_year,
        any_value(market) as market,
        any_value(product) as product,
        any_value(hios_issuer_id) as hios_issuer_id,
        any_value(issuer_name) as issuer_name,
        any_value(plan_marketing_name) as plan_marketing_name,
        any_value(metal_level) as metal_level,
        any_value(plan_type) as plan_type,
        any_value(child_only_offering) as child_only_offering,
        any_value(source_system) as source_system,
        any_value(standardized_plan_option) as standardized_plan_option,
        any_value(ehb_percent_of_total_premium) as ehb_percent_of_total_premium,
        any_value(drug_benefits_integrated_standard) as drug_benefits_integrated_standard,
        any_value(network_url) as network_url,
        any_value(plan_brochure_url) as plan_brochure_url,
        any_value(summary_of_benefits_url) as summary_of_benefits_url,
        any_value(drug_formulary_url) as drug_formulary_url,
        any_value(customer_service_phone_local) as customer_service_phone_local,
        any_value(customer_service_phone_toll_free) as customer_service_phone_toll_free,
        any_value(customer_service_phone_tty) as customer_service_phone_tty
    from unioned
    group by 1

),

final as (

    select
        c.*,
        -- Snapshot vintage: the four QHP files carry independent
        -- `modified` dates (2026-08-10 for three of them, 2026-08-26
        -- for individual medical in the current vintage). We surface
        -- the most-recent of the four QHP dataset vintages so a stale
        -- refresh of any one file bumps the dim's `as_of` accordingly.
        -- Scalar subquery keeps a missing sidecar surfacing as NULL
        -- (caught by the not_null test) instead of dropping rows.
        (
            select max(vintages.modified) as modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key in (
                'qhp_landscape_individual_medical_2026',
                'qhp_landscape_individual_dental_2026',
                'qhp_landscape_shop_medical_2026',
                'qhp_landscape_shop_dental_2026'
            )
        ) as as_of
    from collapsed as c

)

select * from final
