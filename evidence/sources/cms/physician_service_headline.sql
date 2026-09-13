-- Headline stats for the service-level section. All computed from the
-- National grain of `fct_hcpcs_service` so state rows never join with
-- national and totals aren't double-counted.
select
    count(*) as service_rows,
    count(distinct hcpcs_code) as distinct_hcpcs,
    sum(total_services) as total_services,
    sum(total_services * avg_medicare_payment_amount) as total_program_payment,
    median(payment_to_charge_ratio) as median_payment_to_charge,
    sum(case when hcpcs_drug_indicator = 'Y' then 1 end) as drug_rows,
    max(as_of) as as_of
from main_marts.fct_hcpcs_service
