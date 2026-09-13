-- Program-level comparison for the 2023 vintage from
-- fct_medicaid_medicare_drug_spend. `Medicaid Total` is the FFS + MCO
-- sum and is intentionally shown alongside its two components; use
-- `payer` to fold to a two-bar view. Part D total ($275.8B) here comes
-- from the spending-by-drug file and does NOT match the prescriber-
-- profile file's $288.4B shown on the /prescribers page — see the
-- footnote in the page prose.
select
    program_name,
    payer,
    total_spending,
    total_claims,
    total_beneficiaries,
    total_dosage_units,
    spending_per_claim,
    as_of
from main_marts.fct_medicaid_medicare_drug_spend
order by total_spending desc
