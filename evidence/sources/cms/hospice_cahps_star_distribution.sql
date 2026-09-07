-- Distribution of the CAHPS family-caregiver summary star (1-5) plus
-- an `Unrated` bucket. CMS only publishes a star for hospices with
-- enough completed caregiver surveys; the remainder show `Not
-- Applicable` in the source and land here as unrated.
select
    coalesce(cast(star_rating as varchar), 'Unrated') as star_bucket,
    count(*) as hospices
from main_marts.fct_hospice_cahps
where measure_code = 'SUMMARY_STAR_RATING'
group by 1
order by 1
