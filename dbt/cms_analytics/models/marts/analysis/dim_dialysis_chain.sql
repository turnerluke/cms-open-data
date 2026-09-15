-- Chain-group dimension for the DaVita-vs-Fresenius comparative
-- analysis. Collapses `dim_dialysis_facility.chain_organization` (32
-- distinct values in the 2026-08 vintage) into four analytical buckets
-- reused across the chain-analysis marts and the Evidence page:
--
--   * `DaVita`      -- chain_organization = 'DaVita'
--   * `Fresenius`   -- chain_organization = 'Fresenius Medical Care'
--   * `Other chain` -- any other chain_organization value
--                     (i.e. is_chain_owned = true AND not the two
--                     national chains)
--   * `Independent` -- chain_organization = 'Independent'
--                     (staging invariant: iff is_chain_owned = false)
--
-- One row per chain_group (four rows). Records the constituent
-- chain-organization list and facility count so the definition is
-- self-documenting and joinable when a page needs the membership.

with facilities as (

    select * from {{ ref('dim_dialysis_facility') }}

),

classified as (

    select
        ccn,
        chain_organization,
        {{ dialysis_chain_group('chain_organization') }} as chain_group
    from facilities

),

rolled_up as (

    select
        chain_group,
        count(*) as n_facilities,
        count(distinct chain_organization) as n_chain_organizations,
        list_sort(array_agg(distinct chain_organization)) as chain_organization_list
    from classified
    group by 1

),

final as (

    select
        chain_group,
        n_facilities,
        n_chain_organizations,
        chain_organization_list,
        -- as_of pulled from the single-vintage dialysis file so the
        -- dim stays in lockstep with dim_dialysis_facility
        (
            select vintages.modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key = 'dialysis_facility_listing'
        ) as as_of
    from rolled_up

)

select * from final
