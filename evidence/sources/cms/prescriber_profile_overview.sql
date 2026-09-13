-- Headline aggregates from `fct_prescriber_profile` (one row per NPI,
-- no drug-level suppression). Numbers here are strictly larger than the
-- detail-file view built on `fct_prescriber_drug_spending`, because CMS
-- drops any prescriber-drug row with <11 claims from the detail file
-- but keeps those claims inside each prescriber's overall totals.
select
    count(*) as prescribers,
    sum(case when entity_code = 'I' then 1 else 0 end) as individuals,
    sum(case when entity_code = 'O' then 1 else 0 end) as organizations,
    sum(total_claims) as total_claims,
    sum(total_drug_cost) as total_drug_cost,
    -- share of NPIs whose total_beneficiaries is null (CMS suppresses
    -- when the count is 1-10)
    cast(count(*) - count(total_beneficiaries) as double)
    / count(*) as suppressed_beneficiary_share,
    max(as_of) as as_of
from main_marts.fct_prescriber_profile
