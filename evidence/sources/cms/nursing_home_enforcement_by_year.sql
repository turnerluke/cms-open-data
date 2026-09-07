select
    year(action_date) as action_year,
    count(
        case when action_type = 'deficiency' then 1 end
    ) as deficiency_citations,
    count(case when penalty_type = 'Fine' then 1 end) as fines,
    sum(
        case when penalty_type = 'Fine' then fine_amount end
    ) as total_fine_amount,
    count(
        case when penalty_type = 'Payment Denial' then 1 end
    ) as payment_denials
from main_marts.fct_nursing_home_enforcement
group by 1
order by 1
