-- TODO: matching is exact on upper-trimmed names only; a future
-- iteration could map both sources to RxNorm ingredient codes so
-- differently formatted names (dosage-qualified Part B strings,
-- multi-brand HCPCS rows) still conform to one drug.

with part_b as (

    select distinct
        brand_name,
        generic_name
    from {{ ref('stg_cms__medicare_part_b_spending_by_drug') }}
    where brand_name is not null or generic_name is not null

),

part_d as (

    select distinct
        brand_name,
        generic_name
    from {{ ref('stg_cms__part_d_spending_by_drug') }}

),

unioned as (

    select
        upper(brand_name) as brand_name,
        upper(generic_name) as generic_name,
        brand_name as source_brand_name,
        generic_name as source_generic_name,
        'part_b' as source_system
    from part_b
    union all
    select
        upper(brand_name) as brand_name,
        upper(generic_name) as generic_name,
        brand_name as source_brand_name,
        generic_name as source_generic_name,
        'part_d' as source_system
    from part_d

),

conformed as (

    select
        brand_name,
        generic_name,
        -- min() collapses case-only variants within a source to one
        -- deterministic representative spelling
        min(case when source_system = 'part_b' then source_brand_name end)
            as part_b_brand_name,
        min(case when source_system = 'part_b' then source_generic_name end)
            as part_b_generic_name,
        min(case when source_system = 'part_d' then source_brand_name end)
            as part_d_brand_name,
        min(case when source_system = 'part_d' then source_generic_name end)
            as part_d_generic_name,
        bool_or(source_system = 'part_b') as in_part_b,
        bool_or(source_system = 'part_d') as in_part_d
    from unioned
    group by 1, 2

),

final as (

    select
        -- key expression must stay identical to the spend facts' so
        -- their relationship tests hold
        {{ dbt_utils.generate_surrogate_key(['brand_name', 'generic_name']) }}
            as drug_key,
        brand_name,
        generic_name,
        part_b_brand_name,
        part_b_generic_name,
        part_d_brand_name,
        part_d_generic_name,
        in_part_b,
        in_part_d
    from conformed

)

select * from final
