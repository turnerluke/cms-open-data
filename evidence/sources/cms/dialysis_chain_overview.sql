-- Headline scalars for the dialysis chain-comparison page. All fields
-- are single values so the page can `<Value>` them directly.
--
-- `duopoly_share` is DaVita + Fresenius as a fraction of the total
-- Medicare-certified outpatient dialysis population; `duopoly_facilities`
-- is the raw sum. `other_chain_orgs` is the count of distinct chain
-- organizations rolled into the `Other chain` bucket (a long tail of
-- regional operators).
select
    (
        select sum(n_facilities)
        from main_marts.dim_dialysis_chain
    ) as total_facilities,
    (
        select n_facilities
        from main_marts.dim_dialysis_chain
        where chain_group = 'DaVita'
    ) as davita_facilities,
    (
        select n_facilities
        from main_marts.dim_dialysis_chain
        where chain_group = 'Fresenius'
    ) as fresenius_facilities,
    (
        select n_facilities
        from main_marts.dim_dialysis_chain
        where chain_group = 'Other chain'
    ) as other_chain_facilities,
    (
        select n_facilities
        from main_marts.dim_dialysis_chain
        where chain_group = 'Independent'
    ) as independent_facilities,
    (
        select n_chain_organizations
        from main_marts.dim_dialysis_chain
        where chain_group = 'Other chain'
    ) as other_chain_orgs,
    (
        select sum(
            case when chain_group in ('DaVita', 'Fresenius')
                then n_facilities
            end
        )
        from main_marts.dim_dialysis_chain
    ) as duopoly_facilities,
    (
        select
            sum(
                case when chain_group in ('DaVita', 'Fresenius')
                    then n_facilities
                end
            )::double
            / sum(n_facilities)
        from main_marts.dim_dialysis_chain
    ) as duopoly_share,
    (
        select max(as_of) from main_marts.dim_dialysis_chain
    ) as as_of
