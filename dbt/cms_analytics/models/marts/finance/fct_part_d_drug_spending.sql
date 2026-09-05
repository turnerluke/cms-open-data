{#-
    Years covered by the wide staging table. New CMS releases add new
    per-year columns upstream; extend this list (and the staging model)
    when a new data year lands so the unpivot picks it up.
-#}
{% set spending_years = [2020, 2021, 2022, 2023, 2024] %}

with staged as (

    select * from {{ ref('stg_cms__part_d_spending_by_drug') }}

),

unpivoted as (

    {% for year in spending_years %}
        select
            brand_name,
            generic_name,
            manufacturer_name,
            total_manufacturers,
            {{ year }} as spending_year,
            total_spending_{{ year }} as total_spending,
            total_dosage_units_{{ year }} as total_dosage_units,
            total_claims_{{ year }} as total_claims,
            total_beneficiaries_{{ year }} as total_beneficiaries,
            avg_spending_per_dosage_unit_weighted_{{ year }}
                as avg_spending_per_dosage_unit_weighted,
            avg_spending_per_claim_{{ year }} as avg_spending_per_claim,
            avg_spending_per_beneficiary_{{ year }} as avg_spending_per_beneficiary,
            is_outlier_{{ year }} as is_outlier
        from staged
        {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

marketed as (

    -- a year where every metric and the outlier flag are null means
    -- the drug wasn't marketed that year; those rows carry no
    -- information, so drop them
    select *
    from unpivoted
    where
        total_spending is not null
        or total_dosage_units is not null
        or total_claims is not null
        or total_beneficiaries is not null
        or avg_spending_per_dosage_unit_weighted is not null
        or avg_spending_per_claim is not null
        or avg_spending_per_beneficiary is not null
        or is_outlier is not null

),

final as (

    select
        brand_name,
        generic_name,
        manufacturer_name,
        manufacturer_name = 'Overall' as is_manufacturer_rollup,
        total_manufacturers,
        spending_year,
        total_spending,
        total_dosage_units,
        total_claims,
        total_beneficiaries,
        avg_spending_per_dosage_unit_weighted,
        avg_spending_per_claim,
        avg_spending_per_beneficiary,
        total_spending / nullif(total_claims, 0) as spending_per_claim_derived,
        total_spending / nullif(total_beneficiaries, 0)
            as spending_per_beneficiary_derived,
        -- only compare consecutive years: unmarketed years are dropped
        -- above, so a bare lag() could otherwise span a gap
        case
            when lag(spending_year) over drug_years = spending_year - 1
                then total_spending - lag(total_spending) over drug_years
        end as total_spending_yoy_change,
        is_outlier
    from marketed
    window drug_years as (
        partition by brand_name, generic_name, manufacturer_name
        order by spending_year
    )

)

select * from final
