-- State-level payment-per-service for HCPCS 99214 (established patient
-- office visit, moderate complexity) — the highest-payment single
-- (HCPCS, place_of_service) cell in the file at ~$8.0B nationally.
-- Every row is placed on a scatter of state avg payment vs national
-- benchmark, using the inline `national_*` columns.
--
-- Same territory / pseudo-code / null-code filter as
-- `physician_service_state_index.sql` — 50 states + DC only.
select
    geography_code,
    geography_description,
    total_services,
    avg_medicare_payment_amount as state_avg_payment,
    national_avg_medicare_payment_amount as national_avg_payment,
    share_of_national_services,
    avg_medicare_payment_amount
    / nullif(national_avg_medicare_payment_amount, 0) as payment_ratio
from main_marts.fct_physician_service_geography
where
    geography_level = 'State'
    and hcpcs_code = '99214'
    and place_of_service = 'O'
    and geography_code is not null
    and length(geography_code) = 2
    and geography_code not like '9%'
    and geography_code not in ('60', '66', '69', '72', '78')
order by payment_ratio desc
