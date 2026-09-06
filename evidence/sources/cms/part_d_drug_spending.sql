select
    drug_key,
    brand_name,
    generic_name,
    manufacturer_name,
    is_manufacturer_rollup,
    spending_year,
    total_spending,
    total_claims,
    total_beneficiaries,
    spending_per_beneficiary_derived
from main_marts.fct_part_d_drug_spending
