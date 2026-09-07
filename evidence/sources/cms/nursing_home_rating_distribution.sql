with ratings as (

    select
        'Overall' as rating_type,
        1 as sort_order,
        overall_rating as stars
    from main_marts.dim_nursing_home
    union all
    select
        'Health inspection',
        2,
        health_inspection_rating
    from main_marts.dim_nursing_home
    union all
    select
        'Quality measures',
        3,
        qm_rating
    from main_marts.dim_nursing_home
    union all
    select
        'Staffing',
        4,
        staffing_rating
    from main_marts.dim_nursing_home

)

select
    rating_type,
    sort_order,
    stars,
    count(*) as facilities
from ratings
where stars is not null
group by 1, 2, 3
order by sort_order, stars
