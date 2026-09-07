-- Quality-of-patient-care star rating distribution for home health
-- agencies. CMS publishes stars in 0.5-star increments; the buckets
-- below collapse those into whole-star bands plus an `Unrated` bucket
-- for agencies CMS suppresses (roughly a third of agencies — see
-- the star-rating footnote codes in the source dimension).
select
    case
        when quality_of_patient_care_star_rating is null then 'Unrated'
        when quality_of_patient_care_star_rating < 2 then '1.0 – 1.5'
        when quality_of_patient_care_star_rating < 3 then '2.0 – 2.5'
        when quality_of_patient_care_star_rating < 4 then '3.0 – 3.5'
        when quality_of_patient_care_star_rating < 5 then '4.0 – 4.5'
        else '5.0'
    end as star_bracket,
    count(*) as agencies
from main_marts.dim_home_health_agency
group by 1
order by 1
