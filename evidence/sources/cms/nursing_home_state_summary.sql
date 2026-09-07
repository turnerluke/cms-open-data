with homes_by_state as (

    select
        state,
        count(*) as facilities,
        count(overall_rating) as rated_facilities,
        avg(overall_rating) as avg_overall_rating,
        count(
            case when special_focus_status is not null then 1 end
        ) as special_focus_facilities,
        cast(
            count(case when ownership_type like 'For profit%' then 1 end)
            as double
        ) / count(*) as for_profit_share,
        sum(number_of_certified_beds) as certified_beds
    from main_marts.dim_nursing_home
    group by 1

),

state_fines as (

    select
        homes.state,
        count(*) as fines,
        sum(enforcement.fine_amount) as total_fine_amount
    from main_marts.fct_nursing_home_enforcement as enforcement
    inner join main_marts.dim_nursing_home as homes using (ccn)
    where enforcement.penalty_type = 'Fine'
    group by 1

)

select
    homes_by_state.state,
    homes_by_state.facilities,
    homes_by_state.rated_facilities,
    homes_by_state.avg_overall_rating,
    homes_by_state.special_focus_facilities,
    homes_by_state.for_profit_share,
    homes_by_state.certified_beds,
    coalesce(state_fines.fines, 0) as fines,
    coalesce(state_fines.total_fine_amount, 0) as total_fine_amount,
    coalesce(state_fines.total_fine_amount, 0)
    / homes_by_state.facilities as fine_amount_per_facility
from homes_by_state
left join state_fines using (state)
order by homes_by_state.facilities desc
