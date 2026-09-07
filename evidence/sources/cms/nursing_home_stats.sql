select
    (select count(*) from main_marts.dim_nursing_home) as facilities,
    (
        select count(overall_rating) from main_marts.dim_nursing_home
    ) as rated_facilities,
    (
        select median(overall_rating) from main_marts.dim_nursing_home
    ) as median_overall_rating,
    (
        select avg(overall_rating) from main_marts.dim_nursing_home
    ) as avg_overall_rating,
    (
        select count(*) from main_marts.dim_nursing_home
        where special_focus_status = 'SFF'
    ) as sff_facilities,
    (
        select count(*) from main_marts.dim_nursing_home
        where special_focus_status = 'SFF Candidate'
    ) as sff_candidate_facilities,
    (
        select count(*) from main_marts.dim_nursing_home
        where has_abuse_icon
    ) as abuse_icon_facilities,
    (
        select sum(number_of_certified_beds) from main_marts.dim_nursing_home
    ) as certified_beds,
    (
        select count(distinct state) from main_marts.dim_nursing_home
    ) as states,
    (
        select count(*) from main_marts.fct_nursing_home_quality
    ) as quality_rows,
    (
        select count(distinct measure_code)
        from main_marts.fct_nursing_home_quality
    ) as quality_measures,
    (
        select count(*) from main_marts.fct_nursing_home_enforcement
    ) as enforcement_rows,
    (
        select count(*) from main_marts.fct_nursing_home_enforcement
        where penalty_type = 'Fine'
    ) as fines,
    (
        select sum(fine_amount) from main_marts.fct_nursing_home_enforcement
        where penalty_type = 'Fine'
    ) as total_fine_amount,
    (
        select count(*) from main_marts.fct_nursing_home_enforcement
        where penalty_type = 'Payment Denial'
    ) as payment_denials,
    (
        select count(*) from main_marts.fct_nursing_home_enforcement
        where action_type = 'deficiency'
    ) as deficiency_citations,
    (
        select min(action_date) from main_marts.fct_nursing_home_enforcement
        where action_type = 'penalty'
    ) as earliest_penalty_date,
    (select max(as_of) from main_marts.dim_nursing_home) as provider_as_of,
    (
        select max(as_of) from main_marts.fct_nursing_home_quality
    ) as quality_as_of,
    (
        select max(as_of) from main_marts.fct_nursing_home_enforcement
    ) as enforcement_as_of
