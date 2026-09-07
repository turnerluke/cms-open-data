-- Hospice counts by ownership plus their family-caregiver CAHPS
-- summary star rating. Only hospices with a numeric summary star are
-- included in the star average (about a third of hospices — the
-- remainder are unrated in the current vintage).
with hospices as (
    select
        ccn,
        coalesce(ownership_type, 'Unspecified') as ownership_type
    from main_marts.dim_hospice
),

star as (
    select ccn, star_rating
    from main_marts.fct_hospice_cahps
    where measure_code = 'SUMMARY_STAR_RATING' and star_rating is not null
)

select
    hospices.ownership_type,
    count(*) as hospices,
    count(star.star_rating) as hospices_rated,
    avg(star.star_rating) as avg_cahps_star
from hospices
left join star using (ccn)
group by hospices.ownership_type
order by hospices desc
