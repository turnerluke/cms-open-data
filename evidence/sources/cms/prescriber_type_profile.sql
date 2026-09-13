-- Prescriber-type patterns from `fct_prescriber_profile`. Restricted
-- to types with at least 5,000 prescribers so category shares are
-- stable. Rates are computed only over rows where the measure is not
-- suppressed (so the denominator drops when CMS blanked the numerator);
-- brand share uses the sum of brand + generic + other claims as its
-- denominator rather than `total_claims`, because those three splits
-- carry independent suppression and don't reconcile to the row total.
with base as (

    select
        prescriber_type,
        count(*) as prescribers,
        sum(total_claims) as total_claims,
        sum(total_drug_cost) as total_drug_cost,
        sum(brand_total_claims) as brand_claims,
        sum(
            coalesce(brand_total_claims, 0)
            + coalesce(generic_total_claims, 0)
            + coalesce(other_total_claims, 0)
        ) as brand_generic_other_claims,
        sum(opioid_total_claims) as opioid_claims,
        sum(
            case when opioid_total_claims is not null then total_claims end
        ) as opioid_denominator_claims,
        sum(antibiotic_total_claims) as antibiotic_claims,
        sum(
            case when antibiotic_total_claims is not null then total_claims end
        ) as antibiotic_denominator_claims,
        sum(antipsychotic_ge65_total_claims) as antipsychotic_ge65_claims,
        sum(
            case
                when antipsychotic_ge65_total_claims is not null
                    then total_claims
            end
        ) as antipsychotic_ge65_denominator_claims
    from main_marts.fct_prescriber_profile
    where prescriber_type is not null
    group by prescriber_type
    having count(*) >= 5000

)

select
    prescriber_type,
    prescribers,
    total_claims,
    total_drug_cost,
    total_drug_cost / nullif(total_claims, 0) as cost_per_claim,
    brand_claims
    / nullif(brand_generic_other_claims, 0) as brand_share,
    opioid_claims
    / nullif(opioid_denominator_claims, 0) as opioid_rate,
    antibiotic_claims
    / nullif(antibiotic_denominator_claims, 0) as antibiotic_rate,
    antipsychotic_ge65_claims
    / nullif(antipsychotic_ge65_denominator_claims, 0)
        as antipsychotic_ge65_rate
from base
order by total_drug_cost desc
limit 20
