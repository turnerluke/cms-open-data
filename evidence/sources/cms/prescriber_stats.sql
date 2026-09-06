select
    count(*) as total_rows,
    count(distinct f.npi) as prescribers,
    count(distinct upper(f.brand_name) || '|' || upper(f.generic_name)) as drugs,
    sum(f.total_drug_cost) as total_drug_cost,
    sum(f.total_claims) as total_claims,
    cast(count(case when f.total_beneficiaries is null then 1 end) as double)
        / count(*) as suppressed_beneficiary_share,
    cast(count(case when d.drug_key is null then 1 end) as double)
        / count(*) as dim_drug_orphan_share
from main_marts.fct_prescriber_drug_spending as f
left join main_marts.dim_drug as d using (drug_key)
