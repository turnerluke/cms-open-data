-- Individual medical deductibles for silver plans, split by
-- cost-sharing-reduction variant. Silver plans carry the standard
-- variant plus three CSR variants (73/87/94 percent actuarial value)
-- that CMS makes available on income-based sliding scales below 250 %
-- of the federal poverty level.

select
    csr_variant,
    case csr_variant
        when 'standard' then 'Standard silver'
        when '73_percent' then 'CSR 73% (200–250% FPL)'
        when '87_percent' then 'CSR 87% (150–200% FPL)'
        when '94_percent' then 'CSR 94% (100–150% FPL)'
    end as csr_label,
    case csr_variant
        when 'standard' then 0
        when '73_percent' then 1
        when '87_percent' then 2
        when '94_percent' then 3
    end as csr_sort,
    count(*) as plan_county_offerings,
    count(distinct cost_sharing.plan_id) as plans,
    avg(medical_deductible_individual) as avg_deductible_individual,
    median(medical_deductible_individual) as median_deductible_individual,
    avg(medical_moop_individual) as avg_moop_individual,
    median(medical_moop_individual) as median_moop_individual
from main_marts.fct_qhp_cost_sharing as cost_sharing
inner join main_marts.dim_qhp_plan as plans using (plan_id)
where
    plans.product = 'medical'
    and plans.market = 'individual'
    and plans.metal_level = 'Silver'
group by 1
order by csr_sort
