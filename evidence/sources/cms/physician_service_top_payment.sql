-- Top 20 HCPCS × place-of-service cells by total Medicare program
-- payment. Derived at the National grain (no state rows) so the total
-- payment column is the true CMS-published all-USA total.
--
-- `total_program_payment` is `total_services * avg_medicare_payment_amount`
-- — the same convention used elsewhere for provider-population averages.
select
    hcpcs_code,
    hcpcs_description,
    place_of_service,
    hcpcs_drug_indicator,
    total_services,
    total_beneficiaries,
    avg_submitted_charge,
    avg_medicare_payment_amount,
    total_services * avg_medicare_payment_amount as total_program_payment,
    payment_to_charge_ratio
from main_marts.fct_hcpcs_service
order by total_program_payment desc
limit 20
