with date_spine as (

    {{
        dbt_utils.date_spine(
            datepart="day",
            start_date="cast('2013-01-01' as date)",
            end_date="cast('2030-01-01' as date)"
        )
    }}

),

final as (

    select
        cast(date_day as date) as date_day,
        extract(year from date_day) as year_number,
        extract(quarter from date_day) as quarter_of_year,
        extract(month from date_day) as month_of_year,
        monthname(date_day) as month_name,
        extract(day from date_day) as day_of_month,
        isodow(date_day) as day_of_week,
        dayname(date_day) as day_name,
        isodow(date_day) >= 6 as is_weekend
    from date_spine

)

select * from final
