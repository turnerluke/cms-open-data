select
    (select count(*) from main_marts.dim_hospice) as hospices,
    (
        select count(distinct state) from main_marts.dim_hospice
    ) as states,
    (
        select count(distinct ccn)
        from main_marts.fct_hospice_cahps
        where measure_code = 'SUMMARY_STAR_RATING' and star_rating is not null
    ) as hospices_with_cahps_star,
    (
        select avg(star_rating)
        from main_marts.fct_hospice_cahps
        where measure_code = 'SUMMARY_STAR_RATING'
    ) as avg_cahps_star,
    (
        select count(distinct measure_code)
        from main_marts.fct_hospice_quality
    ) as his_hci_measures,
    (
        select count(distinct ccn) from main_marts.fct_hospice_quality
    ) as hospices_with_quality,
    (
        select max(as_of) from main_marts.dim_hospice
    ) as provider_as_of,
    (
        select max(as_of) from main_marts.fct_hospice_quality
    ) as quality_as_of,
    (
        select max(as_of) from main_marts.fct_hospice_cahps
    ) as cahps_as_of,
    (
        select count(*) from main_marts.fct_hospice_quality
    ) as quality_rows,
    (
        select count(*) from main_marts.fct_hospice_cahps
    ) as cahps_rows,
    (
        select count(distinct measure_code)
        from main_marts.fct_hospice_cahps
    ) as cahps_measures
