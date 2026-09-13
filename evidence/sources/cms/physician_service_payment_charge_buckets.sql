-- Distribution of `payment_to_charge_ratio` at the National grain,
-- bucketed into readable brackets. The empirical range is 0.00007–1.0
-- with a median of 0.169, so the sub-30% band holds the bulk of both
-- rows and program dollars.
with buckets as (

    select
        case
            when payment_to_charge_ratio < 0.10 then '<10%'
            when payment_to_charge_ratio < 0.20 then '10-20%'
            when payment_to_charge_ratio < 0.30 then '20-30%'
            when payment_to_charge_ratio < 0.40 then '30-40%'
            when payment_to_charge_ratio < 0.50 then '40-50%'
            when payment_to_charge_ratio < 0.75 then '50-75%'
            else '75-100%'
        end as bucket,
        payment_to_charge_ratio,
        total_services,
        total_services * avg_medicare_payment_amount as program_payment
    from main_marts.fct_hcpcs_service

),

with_order as (

    select
        bucket,
        case bucket
            when '<10%' then 1
            when '10-20%' then 2
            when '20-30%' then 3
            when '30-40%' then 4
            when '40-50%' then 5
            when '50-75%' then 6
            else 7
        end as bucket_order,
        count(*) as service_rows,
        sum(total_services) as total_services,
        sum(program_payment) as program_payment
    from buckets
    group by bucket

)

select
    bucket,
    service_rows,
    total_services,
    program_payment
from with_order
order by bucket_order
