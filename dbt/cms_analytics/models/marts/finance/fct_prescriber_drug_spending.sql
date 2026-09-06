-- TODO: the prescriber source file is a single latest-vintage
-- snapshot with no year column, so this fact has no spending_year.
-- Take the year from dataset-vintage tracking before moving to an
-- npi × drug × year grain.

with staged as (

    select * from {{ ref('stg_cms__medicare_part_d_prescribers_by_provider_and_drug') }}

),

final as (

    select
        npi,
        prescriber_last_org_name,
        prescriber_first_name,
        prescriber_type,
        city,
        state,
        brand_name,
        generic_name,
        -- key expression must stay identical to dim_drug's so the
        -- relationship holds
        {{
            dbt_utils.generate_surrogate_key(
                ["upper(brand_name)", "upper(generic_name)"]
            )
        }} as drug_key,
        total_claims,
        total_30day_fills,
        total_day_supply,
        total_drug_cost,
        total_beneficiaries,
        total_drug_cost / nullif(total_claims, 0) as cost_per_claim,
        total_drug_cost / nullif(total_beneficiaries, 0) as cost_per_beneficiary,
        total_drug_cost / nullif(total_day_supply, 0) as cost_per_day_supplied
    from staged

)

select * from final
