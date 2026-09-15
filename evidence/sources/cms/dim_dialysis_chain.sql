-- Chain-group dimension: one row per analytical chain bucket (DaVita,
-- Fresenius, Other chain, Independent) with the constituent
-- chain-organization list and facility count. See dbt model
-- `dim_dialysis_chain` for the bucket definitions.
select
    chain_group,
    n_facilities,
    n_chain_organizations,
    chain_organization_list,
    as_of
from main_marts.dim_dialysis_chain
