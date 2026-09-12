select
    count(*) as hospitals,
    max(fiscal_year) as fiscal_year,
    avg(total_performance_score) as avg_tps,
    median(total_performance_score) as median_tps,
    min(total_performance_score) as min_tps,
    max(total_performance_score) as max_tps,
    count(
        case
            when
                weighted_clinical_outcomes_score is null
                or weighted_person_and_community_engagement_score is null
                or weighted_safety_score is null
                or weighted_efficiency_and_cost_reduction_score is null
            then 1
        end
    ) as reweighted_hospitals,
    max(as_of) as as_of
from main_marts.fct_hospital_vbp
