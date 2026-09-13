-- Facility vs office rollup at the National grain. Both `total_services`
-- and `total_program_payment` are additive across (hcpcs_code,
-- place_of_service) cells so this doesn't double-count.
select
    case
        when place_of_service = 'F' then 'Facility'
        else 'Office / non-facility'
    end as place,
    count(*) as service_rows,
    count(distinct hcpcs_code) as distinct_hcpcs,
    sum(total_services) as total_services,
    sum(total_services * avg_medicare_payment_amount)
        as total_program_payment,
    sum(total_services * avg_medicare_payment_amount)
    / nullif(sum(total_services), 0) as avg_payment_per_service
from main_marts.fct_hcpcs_service
group by place_of_service
order by place_of_service
