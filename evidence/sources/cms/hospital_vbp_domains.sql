-- One row per VBP domain: average weighted contribution to the
-- 100-point TPS, and how many hospitals were reweighted (NULL) on
-- that domain because CMS lacked enough measures to score them.
select
    'Clinical outcomes' as domain,
    avg(weighted_clinical_outcomes_score) as avg_weighted_score,
    count(weighted_clinical_outcomes_score) as scored_hospitals,
    count(case when weighted_clinical_outcomes_score is null then 1 end)
        as reweighted_hospitals
from main_marts.fct_hospital_vbp
union all
select
    'Person and community engagement',
    avg(weighted_person_and_community_engagement_score),
    count(weighted_person_and_community_engagement_score),
    count(
        case
            when weighted_person_and_community_engagement_score is null then 1
        end
    )
from main_marts.fct_hospital_vbp
union all
select
    'Safety',
    avg(weighted_safety_score),
    count(weighted_safety_score),
    count(case when weighted_safety_score is null then 1 end)
from main_marts.fct_hospital_vbp
union all
select
    'Efficiency and cost reduction',
    avg(weighted_efficiency_and_cost_reduction_score),
    count(weighted_efficiency_and_cost_reduction_score),
    count(
        case
            when weighted_efficiency_and_cost_reduction_score is null then 1
        end
    )
from main_marts.fct_hospital_vbp
