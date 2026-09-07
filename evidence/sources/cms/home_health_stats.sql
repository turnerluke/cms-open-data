select
    (
        select count(*) from main_marts.dim_home_health_agency
    ) as agencies,
    (
        select count(quality_of_patient_care_star_rating)
        from main_marts.dim_home_health_agency
    ) as rated_agencies,
    (
        select avg(quality_of_patient_care_star_rating)
        from main_marts.dim_home_health_agency
    ) as avg_star_rating,
    (
        select count(distinct state)
        from main_marts.dim_home_health_agency
    ) as states,
    (
        select sum(case when offers_nursing_care then 1 else 0 end)
        from main_marts.dim_home_health_agency
    ) as offers_nursing_care,
    (
        select sum(case when offers_physical_therapy then 1 else 0 end)
        from main_marts.dim_home_health_agency
    ) as offers_physical_therapy,
    (
        select sum(case when offers_occupational_therapy then 1 else 0 end)
        from main_marts.dim_home_health_agency
    ) as offers_occupational_therapy,
    (
        select sum(case when offers_speech_pathology then 1 else 0 end)
        from main_marts.dim_home_health_agency
    ) as offers_speech_pathology,
    (
        select sum(case when offers_medical_social_services then 1 else 0 end)
        from main_marts.dim_home_health_agency
    ) as offers_medical_social_services,
    (
        select sum(case when offers_home_health_aide then 1 else 0 end)
        from main_marts.dim_home_health_agency
    ) as offers_home_health_aide,
    (
        select max(as_of) from main_marts.dim_home_health_agency
    ) as provider_as_of,
    (
        select max(as_of) from main_marts.fct_home_health_quality
    ) as quality_as_of,
    (
        select count(*) from main_marts.fct_home_health_quality
    ) as quality_rows,
    (
        select count(distinct measure_code)
        from main_marts.fct_home_health_quality
    ) as quality_measures
