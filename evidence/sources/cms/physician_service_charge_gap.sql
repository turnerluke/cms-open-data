-- Services with the biggest absolute gap between total submitted
-- charges and total Medicare payments. Restricted to HCPCS with
-- meaningful volume (>= 100,000 services nationally) so the ranking
-- isn't dominated by low-volume outliers. National grain only.
select
    hcpcs_code,
    hcpcs_description,
    place_of_service,
    total_services,
    avg_submitted_charge,
    avg_medicare_payment_amount,
    payment_to_charge_ratio,
    total_services
    * (avg_submitted_charge - avg_medicare_payment_amount)
        as charge_minus_payment_dollars
from main_marts.fct_hcpcs_service
where total_services >= 100000
order by charge_minus_payment_dollars desc
limit 15
