select
    hcpcs_code,
    hcpcs_description,
    drug_key,
    brand_name,
    generic_name,
    spending_year,
    total_spending,
    total_claims,
    total_beneficiaries,
    spending_per_beneficiary_derived
from main_marts.fct_part_b_drug_spending
